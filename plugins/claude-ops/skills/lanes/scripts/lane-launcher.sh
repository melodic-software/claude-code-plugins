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
#                                                               startedAt,
#                                                               sessionId, name,
#                                                               status)
#   claude stop <sessionId>                                     stop one session
#   claude plugin marketplace update                            refresh catalog(s)
# There is no `claude agents stop` verb: `stop`/`restart` target the sessionId
# that `agents --json` reports, and ONLY for a name present in the lane config —
# so the wrapper can never stop an unrelated session (e.g. a hand-started one).
#
# PROMPT-FILE STORAGE IS PROVISIONAL. Today prompts live in a session-local
# `.work` dir (the config's `prompt_dir`, default `.work`). A forthcoming
# loop-prompt authoring skill is slated to own durable prompt storage; when it
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

# Guard for a space-separated option that consumes the next token: reject a
# missing value or one that looks like another flag, so `--config --dry-run`
# fails loudly instead of silently swallowing `--dry-run` as the config path.
# Usage: `check_optarg "$1" "${2:-}" || exit 3` (kept out of a subshell so the
# caller's exit actually fires).
check_optarg() {
  [[ -n "${2:-}" && "$2" != -* ]] && return 0
  err "option '$1' requires a non-option argument"
  return 1
}

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
      check_optarg "$1" "${2:-}" || exit 3
      CONFIG="$2"
      shift
      ;;
    --config=*) CONFIG="${1#*=}" ;;
    --repo)
      check_optarg "$1" "${2:-}" || exit 3
      REPO="$2"
      shift
      ;;
    --repo=*) REPO="${1#*=}" ;;
    --no-pull) NO_PULL=1 ;;
    --no-update) NO_UPDATE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --agents-json)
      check_optarg "$1" "${2:-}" || exit 3
      AGENTS_JSON_FILE="$2"
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

# The one prompt-storage seam — repoint here when a durable prompt home exists.
resolve_prompt_dir() {
  local d
  d="$(jq -r '.prompt_dir // ".work"' "$CONFIG")"
  case "$d" in
  /* | [A-Za-z]:[\\/]*) printf '%s' "$d" ;; # absolute (POSIX or Windows drive)
  *) printf '%s' "$REPO/$d" ;;
  esac
}

# --- Session list (real CLI or fixture) --------------------------------------
# Loaded once, in the main shell, into SESSIONS_JSON — not lazily inside a
# `$(...)`/pipe subshell where an `exit` would only kill the subshell and leave
# the script's status at 0 (the same reason the --agents-json existence check
# lives in main). Loading once also gives every lane a single, consistent
# snapshot instead of re-shelling `claude agents --json` per lane.
#
# A genuine live-list failure must NOT be coerced to an empty list: doing so
# makes every lane look stopped, so a real `start` would relaunch lanes that are
# still alive (duplicate sessions) and `status` would report false "stopped".
# load_sessions therefore fails on a live error and main aborts — except under
# --dry-run, which mutates nothing, where previewing against an empty list is
# harmless and preserves the documented offline-dry-run behaviour.
#
# `claude agents --json` (no --all) lists ACTIVE sessions only — interactive and
# running background; completed/terminal background sessions are excluded by the
# CLI (they surface only under --all, carrying a `state` like "done" rather than
# an active `status`). A name match here is therefore already a live-lane match.
# Do NOT add --all without also filtering terminal sessions out of this lookup.
SESSIONS_JSON=""

load_sessions() {
  local raw
  if [[ -n "$AGENTS_JSON_FILE" ]]; then
    raw="$(cat "$AGENTS_JSON_FILE")" || return 1
  else
    raw="$(claude agents --json)" || {
      ((DRY_RUN)) && {
        SESSIONS_JSON='[]'
        return 0
      }
      return 1
    }
  fi
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$raw" || return 1
  SESSIONS_JSON="$raw"
}

# sessionId of a running session with the given name (empty if none). If several
# match, the most recently started wins.
running_session_id() {
  local name="$1"
  jq -r --arg n "$name" \
    '[ .[] | select(.name == $n) ] | sort_by(.startedAt) | last | .sessionId // empty' \
    <<<"$SESSIONS_JSON"
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

# Returns: 0 stopped OK · 2 was not running · other = `claude stop` failed
# (its exit code). Callers must distinguish 2 (benign) from a real stop failure.
stop_lane_if_running() {
  local name="$1" sid
  sid="$(running_session_id "$name")"
  [[ -n "$sid" ]] || return 2
  info "  stop $name ($sid)"
  run claude stop "$sid"
}

# --- Refresh step (pull + marketplace update) --------------------------------
refresh_repo_and_plugins() {
  local rc=0
  if ((NO_PULL)); then
    info "skip git pull (--no-pull)"
  else
    info "git pull --ff-only ($REPO)"
    run git -C "$REPO" pull --ff-only || rc=1
  fi
  if ((NO_UPDATE)); then
    info "skip plugin marketplace update (--no-update)"
  else
    info "claude plugin marketplace update"
    run claude plugin marketplace update || rc=1
  fi
  return "$rc"
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

  local i name model effort prompt_path failures=0
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
    # A per-lane callback failure must not abort the sweep (other lanes still
    # get their turn) but must surface in the aggregate exit status.
    "$callback" "$name" "$model" "$effort" "$prompt_path" || failures=1
  done
  return "$failures"
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
  stop_lane_if_running "$name"
  local s=$?
  # A genuine stop failure (not the benign "was not running", 2) means the old
  # session may still be alive — relaunching would create a second session under
  # the same name, so refuse and surface the failure.
  if [[ $s -ne 0 && $s -ne 2 ]]; then
    err "  $name — stop failed; not relaunching (would duplicate the session name)"
    return 1
  fi
  info "  start $name${model:+ --model $model}${effort:+ --effort $effort}"
  launch_lane "$name" "$model" "$effort" "$prompt_path"
}

_stop_one() {
  local name="$1"
  stop_lane_if_running "$name"
  case $? in
  0) : ;;
  2) info "  $name — not running" ;;
  *)
    err "  $name — stop failed"
    return 1
    ;;
  esac
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

# scope suffix for the header line, e.g. " (work babysit)" when lanes are named.
lane_scope() { ((${#TARGET_LANES[@]})) && printf ' (%s)' "${TARGET_LANES[*]}"; }

action_start() {
  local rc=0
  info "== lanes: start =="
  refresh_repo_and_plugins || rc=1
  info "lanes:"
  for_each_lane _start_one || rc=1
  return "$rc"
}

action_restart() {
  local rc=0
  info "== lanes: restart$(lane_scope) =="
  refresh_repo_and_plugins || rc=1
  info "lanes:"
  for_each_lane _restart_one || rc=1
  return "$rc"
}

action_stop() {
  info "== lanes: stop$(lane_scope) =="
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
  [[ -z "$AGENTS_JSON_FILE" || -f "$AGENTS_JSON_FILE" ]] || {
    err "agents-json file not found: $AGENTS_JSON_FILE"
    exit 4
  }
  load_sessions || {
    if [[ -n "$AGENTS_JSON_FILE" ]]; then
      err "agents-json file is not a JSON array: $AGENTS_JSON_FILE"
    else
      err "could not list sessions: 'claude agents --json' failed — aborting so start/stop never act on fabricated state"
    fi
    exit 4
  }
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
