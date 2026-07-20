#!/usr/bin/env bash
# lane-launcher.sh — start/restart/stop/status loop lanes as background Claude
# Code sessions seeded from canonical prompt files.
#
# The morning refresh ritual — cancel each loop, clear, re-paste its canonical
# prompt across N lanes — collapses to one command. `start`/`restart` pull the
# repo and refresh the plugin marketplace, then launch each configured lane as a
# named background session seeded with the lane's canonical prompt file.
# `status`/`stop` read and manage those sessions through the CLI's own
# background-session surface.
#
# Verified CLI surface (claude 2.1.215 — see the skill's Verification section):
#   claude --bg -n <name> [--model M] [--effort E] "<prompt>"   launch, return now
#   claude agents --json                                        list sessions
#                                                               (pid, cwd, kind,
#                                                               sessionId, name,
#                                                               status)
#   claude stop <sessionId>                                     stop one session
#   claude plugin marketplace update                            refresh catalog(s)
# There is no `claude agents stop` verb: `stop`/`restart` target the sessionId
# that `agents --json` reports, and ONLY for a name present in the lane config —
# so the wrapper can never stop an unrelated session (e.g. a hand-started one).
#
# PROMPT-FILE STORAGE IS PROVISIONAL. Today prompts live in a session-local
# `.work` dir (the config's `prompt_dir`, default `.work`). Issue #480
# (loop-prompt authoring skill) is slated to own durable prompt storage; when it
# lands, repoint `prompt_dir` at that home — the resolution seam is the single
# `resolve_prompt_dir` function below and nothing else.
#
# Usage:
#   lane-launcher.sh [start]              pull + update, launch lanes not running
#   lane-launcher.sh restart [lane...]    stop then start (all lanes, or named)
#   lane-launcher.sh status               per-lane running state
#   lane-launcher.sh stop [lane...]       stop running lanes (all, or named)
#
# Options:
#   --config FILE      lane config JSON (default resolution order below)
#   --repo DIR         repo root for git pull + default launch cwd
#                      (default: the git toplevel of the current directory)
#   --no-pull          skip the git pull step (start / restart)
#   --no-update        skip the plugin marketplace update step (start / restart)
#   --dry-run          print the commands that would run; mutate nothing
#   --agents-json FILE read the session list from FILE instead of
#                      `claude agents --json` (offline / scripted / test reuse)
#   --help
#
# Config resolution (first hit wins):
#   --config FILE  →  $CLAUDE_OPS_LANES_CONFIG  →  <repo>/.work/lanes.json
#
# Config schema (see context/config.md for the full contract):
#   { "prompt_dir": ".work",
#     "lanes": [ {"name":"work","prompt":"work.md","model":"opus","effort":"high"} ] }
#   prompt_dir  optional; base for relative `prompt` paths; default ".work".
#   name        required; the lane's session name (also the --name value).
#   prompt      required; path to the canonical prompt file (absolute, or
#               relative to prompt_dir).
#   model       optional; passed as --model.
#   effort      optional; passed as --effort (low|medium|high|xhigh|max).
#
# Exit codes:
#   0  ok
#   3  invalid argument / malformed config
#   4  prerequisite missing (claude or jq), or repo / config could not be resolved

set -uo pipefail

VALID_EFFORTS="low medium high xhigh max"

ACTION="start"
CONFIG=""
REPO=""
NO_PULL=0
NO_UPDATE=0
DRY_RUN=0
AGENTS_JSON_FILE=""
declare -a TARGET_LANES=()

# --- Small emitters -----------------------------------------------------------
err() { printf 'ERROR: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

# Print the leading comment header (everything after the shebang up to the first
# non-comment line), stripped of the leading '# '. Robust to header length so a
# reformat never bleeds code into --help.
usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

# --- Argument parse -----------------------------------------------------------
# First non-option token is the action; remaining non-option tokens are lane
# names (targets for restart/stop).
parse_args() {
  local seen_action=0
  while (($#)); do
    case "$1" in
    start | restart | status | stop)
      if ((seen_action)); then TARGET_LANES+=("$1"); else
        ACTION="$1"
        seen_action=1
      fi
      ;;
    --config)
      CONFIG="${2:-}"
      shift
      ;;
    --config=*) CONFIG="${1#*=}" ;;
    --repo)
      REPO="${2:-}"
      shift
      ;;
    --repo=*) REPO="${1#*=}" ;;
    --no-pull) NO_PULL=1 ;;
    --no-update) NO_UPDATE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --agents-json)
      AGENTS_JSON_FILE="${2:-}"
      shift
      ;;
    --agents-json=*) AGENTS_JSON_FILE="${1#*=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      while (($#)); do
        TARGET_LANES+=("$1")
        shift
      done
      break
      ;;
    -*)
      err "unknown option: $1"
      exit 3
      ;;
    *)
      # A bare token before the action is an unknown action; after it, a lane.
      if ((seen_action)); then TARGET_LANES+=("$1"); else
        err "unknown action: $1"
        exit 3
      fi
      ;;
    esac
    shift
  done
}

# --- Prerequisites ------------------------------------------------------------
require_jq() {
  command -v jq >/dev/null 2>&1 || {
    err "jq not found (required)"
    exit 4
  }
}

# `claude` is only needed for real mutating/reading calls. Dry runs and
# fixture-fed (--agents-json) reads must work with no CLI installed.
require_claude() {
  ((DRY_RUN)) && return 0
  # A fixture-fed status read (--agents-json) makes no claude call, so it works
  # fully offline as documented; only the paths that actually shell out to
  # claude (launch / stop / marketplace update, or a live agents list) need it.
  [[ "$ACTION" == "status" && -n "$AGENTS_JSON_FILE" ]] && return 0
  command -v claude >/dev/null 2>&1 || {
    err "claude CLI not found (required)"
    exit 4
  }
}

# --- Repo + config resolution -------------------------------------------------
resolve_repo() {
  if [[ -n "$REPO" ]]; then
    [[ -d "$REPO" ]] || {
      err "repo not a directory: $REPO"
      exit 4
    }
    REPO="$(cd "$REPO" && pwd)"
    return 0
  fi
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    {
      err "not inside a git repo; pass --repo DIR"
      exit 4
    }
}

resolve_config() {
  if [[ -z "$CONFIG" ]]; then
    CONFIG="${CLAUDE_OPS_LANES_CONFIG:-$REPO/.work/lanes.json}"
  fi
  [[ -f "$CONFIG" ]] || {
    err "lane config not found: $CONFIG"
    exit 4
  }
  jq -e . "$CONFIG" >/dev/null 2>&1 || {
    err "lane config is not valid JSON: $CONFIG"
    exit 3
  }
  local n
  n="$(jq -r '(.lanes // []) | length' "$CONFIG")"
  [[ "$n" -gt 0 ]] || {
    err "lane config has no lanes: $CONFIG"
    exit 3
  }
}

# The one prompt-storage seam. #480 will repoint this at a durable home.
resolve_prompt_dir() {
  local d
  d="$(jq -r '.prompt_dir // ".work"' "$CONFIG")"
  case "$d" in
  /* | [A-Za-z]:[\\/]*) printf '%s' "$d" ;; # absolute (POSIX or Windows drive)
  *) printf '%s' "$REPO/$d" ;;
  esac
}

# --- Session list (real CLI or fixture) --------------------------------------
sessions_json() {
  if [[ -n "$AGENTS_JSON_FILE" ]]; then
    [[ -f "$AGENTS_JSON_FILE" ]] || {
      err "agents-json file not found: $AGENTS_JSON_FILE"
      exit 4
    }
    cat "$AGENTS_JSON_FILE"
  else
    claude agents --json 2>/dev/null || echo '[]'
  fi
}

# sessionId of a running session with the given name (empty if none). If several
# match, the most recently started wins.
running_session_id() {
  local name="$1"
  sessions_json | jq -r --arg n "$name" \
    '[ .[] | select(.name == $n) ] | sort_by(.startedAt) | last | .sessionId // empty'
}

# --- Per-lane field extraction ------------------------------------------------
lane_field() { jq -r --argjson i "$1" --arg k "$2" '.lanes[$i][$k] // ""' "$CONFIG"; }

# Absolute path to a lane's prompt file.
lane_prompt_path() {
  local raw="$1" pdir="$2"
  case "$raw" in
  /* | [A-Za-z]:[\\/]*) printf '%s' "$raw" ;;
  *) printf '%s' "$pdir/$raw" ;;
  esac
}

# --- Command runner -----------------------------------------------------------
# Echoes the command; runs it unless --dry-run.
run() {
  if ((DRY_RUN)); then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# --- Lane launch --------------------------------------------------------------
launch_lane() {
  local name="$1" model="$2" effort="$3" prompt_path="$4"

  if [[ ! -f "$prompt_path" ]]; then
    err "lane '$name': prompt file not found: $prompt_path — skipped"
    return 1
  fi
  if [[ ! -s "$prompt_path" ]]; then
    err "lane '$name': prompt file is empty: $prompt_path — skipped"
    return 1
  fi
  if [[ -n "$effort" ]] && [[ " $VALID_EFFORTS " != *" $effort "* ]]; then
    err "lane '$name': invalid effort '$effort' (want: $VALID_EFFORTS) — skipped"
    return 1
  fi

  local -a cmd=(claude --bg -n "$name")
  [[ -n "$model" ]] && cmd+=(--model "$model")
  [[ -n "$effort" ]] && cmd+=(--effort "$effort")

  if ((DRY_RUN)); then
    # Keep the seeded prompt out of the echoed command — show a size placeholder.
    local bytes
    bytes="$(wc -c <"$prompt_path" | tr -d ' ')"
    printf 'DRY-RUN:'
    printf ' %q' "${cmd[@]}"
    printf ' %q\n' "<prompt: $prompt_path (${bytes}B)>"
    return 0
  fi

  local prompt
  prompt="$(cat "$prompt_path")"
  cmd+=("$prompt")
  (cd "$REPO" && "${cmd[@]}")
}

stop_lane_if_running() {
  local name="$1" sid
  sid="$(running_session_id "$name")"
  if [[ -n "$sid" ]]; then
    info "  stop $name ($sid)"
    run claude stop "$sid"
    return 0
  fi
  return 1
}

# --- Refresh step (pull + marketplace update) --------------------------------
refresh_repo_and_plugins() {
  if ((NO_PULL)); then
    info "skip git pull (--no-pull)"
  else
    info "git pull --ff-only ($REPO)"
    run git -C "$REPO" pull --ff-only
  fi
  if ((NO_UPDATE)); then
    info "skip plugin marketplace update (--no-update)"
  else
    info "claude plugin marketplace update"
    run claude plugin marketplace update
  fi
}

# --- Lane iteration helper ----------------------------------------------------
# Runs `callback <name> <model> <effort> <prompt_path>` for every lane, or only
# the lanes named in TARGET_LANES. Unknown target names are an error.
for_each_lane() {
  local callback="$1" pdir
  pdir="$(resolve_prompt_dir)"
  local count
  count="$(jq -r '.lanes | length' "$CONFIG")"

  # Validate any explicit targets against the config first.
  if ((${#TARGET_LANES[@]})); then
    local t known
    for t in "${TARGET_LANES[@]}"; do
      known="$(jq -r --arg n "$t" '[.lanes[].name] | index($n) // "no"' "$CONFIG")"
      [[ "$known" != "no" ]] || {
        err "unknown lane '$t' (not in $CONFIG)"
        exit 3
      }
    done
  fi

  local i name model effort prompt_path
  for ((i = 0; i < count; i++)); do
    name="$(lane_field "$i" name)"
    [[ -n "$name" ]] || {
      err "config lane #$i has no name"
      exit 3
    }
    if ((${#TARGET_LANES[@]})); then
      printf '%s\n' "${TARGET_LANES[@]}" | grep -qxF "$name" || continue
    fi
    model="$(lane_field "$i" model)"
    effort="$(lane_field "$i" effort)"
    prompt_path="$(lane_prompt_path "$(lane_field "$i" prompt)" "$pdir")"
    "$callback" "$name" "$model" "$effort" "$prompt_path"
  done
}

# --- Actions ------------------------------------------------------------------
_start_one() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" sid
  sid="$(running_session_id "$name")"
  if [[ -n "$sid" ]]; then
    info "  skip $name — already running ($sid)"
    return 0
  fi
  info "  start $name${model:+ --model $model}${effort:+ --effort $effort}"
  launch_lane "$name" "$model" "$effort" "$prompt_path"
}

_restart_one() {
  local name="$1" model="$2" effort="$3" prompt_path="$4"
  stop_lane_if_running "$name" || true
  info "  start $name${model:+ --model $model}${effort:+ --effort $effort}"
  launch_lane "$name" "$model" "$effort" "$prompt_path"
}

_stop_one() {
  local name="$1"
  stop_lane_if_running "$name" || info "  $name — not running"
}

_status_one() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" sid state="stopped"
  sid="$(running_session_id "$name")"
  [[ -n "$sid" ]] && state="running"
  local pflag=""
  [[ -f "$prompt_path" ]] || pflag=" [prompt MISSING]"
  printf '  %-12s %-8s %-8s %-8s %s%s\n' \
    "$name" "${model:-–}" "${effort:-–}" "$state" "${sid:-–}" "$pflag"
}

action_start() {
  info "== lanes: start =="
  refresh_repo_and_plugins
  info "lanes:"
  for_each_lane _start_one
}

action_restart() {
  info "== lanes: restart${TARGET_LANES:+ (${TARGET_LANES[*]})} =="
  refresh_repo_and_plugins
  info "lanes:"
  for_each_lane _restart_one
}

action_stop() {
  info "== lanes: stop${TARGET_LANES:+ (${TARGET_LANES[*]})} =="
  for_each_lane _stop_one
}

action_status() {
  info "== lanes: status =="
  printf '  %-12s %-8s %-8s %-8s %s\n' "LANE" "MODEL" "EFFORT" "STATE" "SESSION"
  for_each_lane _status_one
}

# --- Main ---------------------------------------------------------------------
main() {
  parse_args "$@"
  require_jq
  require_claude
  resolve_repo
  resolve_config
  case "$ACTION" in
  start) action_start ;;
  restart) action_restart ;;
  status) action_status ;;
  stop) action_stop ;;
  *)
    err "unknown action: $ACTION"
    exit 3
    ;;
  esac
}

main "$@"
