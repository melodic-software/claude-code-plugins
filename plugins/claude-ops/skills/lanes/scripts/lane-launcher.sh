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
# Verified CLI surface (claude 2.1.215 — see the skill's Verification section;
# --settings re-verified against the CLI reference, 2026-07-25):
#   claude --bg -n <name> [--model M] [--effort E] [--settings JSON] "<prompt>"
#                                                               launch, return now
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
#   --data-dir DIR     base dir for the per-lane launch-commit marker (below);
#                      default: $CLAUDE_PLUGIN_DATA env var if set, else
#                      ~/.claude/plugins/data/claude-ops. NOTE: CLAUDE_PLUGIN_DATA
#                      is exported to hook/MCP/LSP subprocesses but NOT to a
#                      script a skill shells out to via the Bash tool (Claude
#                      Code plugins-reference, "Environment variables") — the
#                      lanes skill's SKILL.md passes --data-dir explicitly with
#                      the inline-substituted value so a real Claude Code
#                      session resolves the correct marketplace-qualified
#                      directory; this env-var/fallback path only kicks in for
#                      a direct/manual invocation (tests, a hand-run shell).
#   --gate-arm-script FILE
#                      override discovery of the autonomy plugin's
#                      lane-stop-gate-arm.sh (tests / dev checkouts). Default
#                      discovery walks this script's own install anchor —
#                      <config>/plugins/cache/*/autonomy/*/hooks/ — never an
#                      environment-derived path (see "Lane-stop gate arming").
#   --help
#
# Launch-commit marker (#792):
#   After the pre-launch `git pull` (start/restart), the repo HEAD is captured
#   once and, for every lane actually (re)started this run, written to
#   `<data-dir>/lanes/<repo-key>/<lane>-launch-commit` (bare 40/64-hex SHA +
#   newline; <repo-key> digests the canonical repo path, so same-named lanes in
#   different repos never share a marker — recompute it by hand with
#   `printf '%s' "$(git rev-parse --show-toplevel)" | git hash-object --stdin`) —
#   the `<lane-launch-commit>` context/refresh.md's staleness probe reads. A
#   lane skipped by `start` (already running) keeps its existing marker
#   untouched. Best-effort: a write failure (or an unresolvable HEAD) warns on
#   stderr but never fails an already-launched session — and removes any marker
#   the PREVIOUS launch left, so the probe skips rather than trusting a commit
#   this session never launched at. The lane name is the marker's filename, so
#   config preflight rejects a name that is not a single path component.
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
#   effort      optional; passed as --effort (low|medium|high|xhigh|max|ultracode).
#               ultracode additionally requires the installed CLI to meet
#               ULTRACODE_MIN_VERSION; a lane below it is skipped, not launched.
#   settings    optional; a JSON OBJECT passed inline as --settings for that
#               session only (e.g. a pluginConfigs override opting the lane into
#               the autonomy plugin's lane-stop gate). Non-object values are
#               rejected.
#
# Lane-stop gate arming (#1784):
#   A lane whose settings request the autonomy lane-stop gate
#   (pluginConfigs["autonomy[@…]"].options.lane_stop_gate_enabled == true) is
#   ARMED at launch: the launcher generates a random arm id, runs the autonomy
#   plugin's hooks/lane-stop-gate-arm.sh (which writes a per-session record
#   under autonomy's own install-derived data directory), and injects the id
#   into the lane's --settings as lane_stop_gate_arm_id. The gate honors the
#   record — never the bare CLAUDE_PLUGIN_OPTION_* environment, which a watched
#   repository's own settings.json `env` block can populate. FAIL-CLOSED at
#   launch: a lane that requests the gate but cannot be armed (helper missing,
#   arming error, managed-settings veto) is skipped with an error — launching
#   it silently ungated would defeat the operator's request. Arm-helper
#   discovery uses the launcher's own plugins/cache install anchor (or the
#   --gate-arm-script override); an env-derived location would hand the same
#   repo env block the redirect this design closes.
#
# Exit codes:
#   0  ok
#   3  invalid argument / malformed config
#   4  prerequisite missing (claude or jq), or repo / config could not be resolved

set -uo pipefail

VALID_EFFORTS="low medium high xhigh max ultracode"

# `ultracode` is the one effort upstream gates on a CLI version, so it is the one
# the static allowlist cannot settle on its own. Upstream documents the floor but
# not what an older CLI does with the value, so the launcher refuses rather than
# guessing — restart preflights this BEFORE stopping, keeping a healthy lane up.
ULTRACODE_MIN_VERSION="2.1.203"

# Compared component by component in awk — deliberately NOT `sort -V`, which is a
# GNU-only construct this repo's portability lane rejects. Missing components
# compare as 0, so "2.2" reads as 2.2.0.
version_at_least() { # <candidate> <minimum>
  [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]] || return 1
  awk -F. -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".")
    n = (na > nb ? na : nb)
    for (i = 1; i <= n; i++) {
      av = (i <= na ? x[i] + 0 : 0); bv = (i <= nb ? y[i] + 0 : 0)
      if (av > bv) exit 0
      if (av < bv) exit 1
    }
    exit 0
  }' 2>/dev/null
}

# Memoized: every lane in a run shares one `claude --version` probe.
CLI_VERSION_CACHE=""
cli_version() {
  if [[ -z "$CLI_VERSION_CACHE" ]]; then
    CLI_VERSION_CACHE="$(claude --version 2>/dev/null | tr -d '\r' |
      grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    [[ -z "$CLI_VERSION_CACHE" ]] && CLI_VERSION_CACHE="unknown"
  fi
  printf '%s' "$CLI_VERSION_CACHE"
}

ACTION="start"
CONFIG=""
REPO=""
NO_PULL=0
NO_UPDATE=0
DRY_RUN=0
AGENTS_JSON_FILE=""
DATA_DIR_OVERRIDE=""
GATE_ARM_SCRIPT_OVERRIDE=""
LAUNCH_COMMIT=""
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
    --data-dir)
      check_optarg "$1" "${2:-}" || exit 3
      DATA_DIR_OVERRIDE="$2"
      shift
      ;;
    --data-dir=*) DATA_DIR_OVERRIDE="${1#*=}" ;;
    --gate-arm-script)
      check_optarg "$1" "${2:-}" || exit 3
      GATE_ARM_SCRIPT_OVERRIDE="$2"
      shift
      ;;
    --gate-arm-script=*) GATE_ARM_SCRIPT_OVERRIDE="${1#*=}" ;;
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
  # Lane names are the safety key: stop/restart resolve a sessionId by name and
  # every action snapshots sessions once, so a duplicated name would launch two
  # same-named sessions while stop reaches only the most-recent one. Reject it at
  # config time rather than silently acting on an ambiguous set.
  local dupes
  dupes="$(jq -r '[.lanes[].name | select(. != null)] | group_by(.) | map(select(length > 1) | .[0]) | join(", ")' "$CONFIG")"
  [[ -z "$dupes" ]] || {
    err "lane config has duplicate lane names: $dupes (names must be unique): $CONFIG"
    exit 3
  }
  # The name is also a path component: it keys the per-lane launch-commit marker
  # at <data-dir>/lanes/<name>-launch-commit (#792). A name carrying a path
  # separator (or `.`/`..`) would escape that directory and let two distinct
  # lanes — say `work` and `group/../work` — share one marker file, so a
  # targeted restart of one would make the other's staleness probe read a launch
  # commit it never launched at. Reject rather than silently encode, so the
  # documented marker path stays literally true for every accepted name.
  local traversal
  traversal="$(jq -r '
    [ .lanes[].name
      | select(. != null)
      | select(test("[/\\\\]") or . == "." or . == "..") ] | join(", ")' "$CONFIG")"
  [[ -z "$traversal" ]] || {
    err "lane config has lane names that are not usable as a path component: $traversal"
    err "  (a name must not contain '/' or '\\', or be '.' or '..'): $CONFIG"
    exit 3
  }
  # The scalar lane fields are strings, and typing them HERE is what lets
  # `lane_field` keep answering "" for an absent field: `// ""` is jq's
  # alternative operator, so it fires on any falsy value — a mistyped
  # `"effort": false` collapsed to the same "" an unset field produces and the
  # lane launched with no effort at all, silently. A wrong type is a config
  # error like the duplicate/traversal names above, not a per-lane skip. An
  # explicit `null` is the JSON spelling of "no value" and stays equivalent to
  # an absent field. `settings` is deliberately NOT typed here — it is checked
  # per lane in validate_launch_inputs, which skips just that lane.
  local mistyped
  mistyped="$(jq -r '
    [ .lanes
      | to_entries[]
      | .key as $i
      | .value
      | to_entries[]
      | select(.key == "name" or .key == "model" or .key == "effort" or .key == "prompt")
      | select(.value != null and (.value | type) != "string")
      | "lane #\($i) .\(.key) is \(.value | type)" ]
    | join(", ")' "$CONFIG")"
  [[ -z "$mistyped" ]] || {
    err "lane config has non-string values for string fields: $mistyped"
    err "  (name/model/effort/prompt must be JSON strings): $CONFIG"
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

# --- Launch-commit marker (#792) ----------------------------------------------
# Base data dir: --data-dir, else $CLAUDE_PLUGIN_DATA, else the same
# ~/.claude/plugins/data/claude-ops fallback check-all.sh uses for a machine
# where the harness does not export CLAUDE_PLUGIN_DATA (e.g. a direct script
# invocation outside a Claude Code session, as in the test suite).
resolve_data_dir() {
  local base="${DATA_DIR_OVERRIDE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/claude-ops}}"
  printf '%s/lanes' "${base%/}"
}

# The data dir is plugin-wide, but a lane name is only unique WITHIN one repo:
# this launcher manages lanes in any repo `--repo` points at, and `work` is a
# conventional name everywhere. Without a repo component, starting `work` in
# repo B would overwrite repo A's marker, and A's probe would then diff against
# a SHA from an unrelated history — usually an "invalid revision" error, at best
# a silently wrong answer.
#
# Two properties the key must have, both learned the hard way:
#   * Injective. A character-folding scheme (e.g. `tr -c 'A-Za-z0-9_-' '-'`)
#     collapses `/repos/foo-bar` and `/repos/foo/bar` onto one key, which is the
#     very collision this component exists to prevent. `git hash-object` over
#     the exact path string cannot.
#   * Derived from the CANONICAL path. `--repo` may name a symlink, which
#     `resolve_repo` preserves; context/refresh.md's probe independently asks
#     git for the toplevel. Both sides therefore key on `git rev-parse
#     --show-toplevel` — git reports the physical, symlink-resolved working
#     tree — so the probe always looks where the launcher wrote.
# Falls back to $REPO only when the directory is not a git repo at all, where
# the probe could not run anyway. Computed once per run.
REPO_MARKER_KEY=""
repo_marker_key() {
  if [[ -z "$REPO_MARKER_KEY" ]]; then
    local top
    top="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || top=""
    [[ -n "$top" ]] || top="$REPO"
    REPO_MARKER_KEY="$(printf '%s' "$top" | git hash-object --stdin 2>/dev/null)"
    [[ -n "$REPO_MARKER_KEY" ]] || REPO_MARKER_KEY="unkeyed"
  fi
  printf '%s' "$REPO_MARKER_KEY"
}

launch_commit_marker_path() {
  printf '%s/%s/%s-launch-commit' "$(resolve_data_dir)" "$(repo_marker_key)" "$1"
}

# Captures the repo HEAD once per start/restart invocation (after the
# pre-launch pull, if any ran). A hex-only `git rev-parse HEAD` value carries
# no injection risk; empty on failure (detached-HEAD-less/unresolvable repo),
# which downstream write_launch_commit_marker treats as "skip, don't write".
capture_launch_commit() {
  LAUNCH_COMMIT="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)" || LAUNCH_COMMIT=""
}

# A launch that cannot record its own commit must not leave the PREVIOUS
# launch's marker on disk: the refresh probe would read that older commit as
# this session's launch point and keep reporting merges the session already
# consumed — indefinitely, since nothing later rewrites it. Removing it degrades
# the probe to its honest "no marker → skip" branch instead. Best-effort like
# the write itself: a failed removal only warns.
invalidate_launch_commit_marker() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  if rm -f "$path" 2>/dev/null; then
    err "  removed the previous launch's marker so the staleness probe skips rather than trusts it: $path"
  else
    err "  stale launch-commit marker could not be removed — the staleness probe will read an obsolete commit: $path"
  fi
}

# Writes the captured launch commit to <data-dir>/lanes/<name>-launch-commit.
# Best-effort and always returns 0: a marker write failure must never fail a
# lane that has already (or would already) launch — only warn on stderr. The
# caller passes the already-resolved marker path (launch_lane resolves it
# once per lane).
write_launch_commit_marker() {
  local path="$1"
  if [[ -z "$LAUNCH_COMMIT" ]]; then
    err "launch-commit marker skipped for $path: repo HEAD could not be resolved"
    invalidate_launch_commit_marker "$path"
    return 0
  fi
  if ! mkdir -p "$(dirname "$path")" 2>/dev/null || ! printf '%s\n' "$LAUNCH_COMMIT" >"$path" 2>/dev/null; then
    err "launch-commit marker write failed: $path"
    invalidate_launch_commit_marker "$path"
  fi
  return 0
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

# sessionId of a running lane session with the given name (empty if none). If
# several match, the most recently started wins.
#
# Restricted to `kind == "background"`: lanes are always launched with `--bg`, so
# a lane is by construction a background session. An interactive window that
# happens to share a lane name (e.g. a hand-started `work`) is therefore never
# matched — never skipped by `start`, never handed to `claude stop`. Since a real
# lane is always background, this can only exclude non-lane sessions, never a live
# lane, so it cannot cause a duplicate launch.
running_session_id() {
  local name="$1"
  jq -r --arg n "$name" \
    '[ .[] | select(.name == $n and .kind == "background") ] | sort_by(.startedAt) | last | .sessionId // empty' \
    <<<"$SESSIONS_JSON"
}

# --- Per-lane field extraction ------------------------------------------------
# String lane field; "" when absent. The `//` alternative is falsy-triggered
# rather than presence-triggered, so "" would also be the answer for a
# non-string value — resolve_config rejects those at config time, which is what
# keeps "" here meaning exactly one thing: the field is absent.
lane_field() { jq -r --argjson i "$1" --arg k "$2" '.lanes[$i][$k] // ""' "$CONFIG"; }

# Structured (non-string) lane field, emitted as compact JSON; empty ONLY when
# the field is absent. Used for `settings`, whose value is a JSON object rather
# than a scalar. Presence is `has`, not `//`: the alternative operator fires on
# every falsy value, so a `"settings": false` yielded `empty` and reached bash
# as "" — indistinguishable from unset. validate_launch_inputs guards its type
# check on `[[ -n "$settings" ]]`, so that check was skipped entirely and
# launch_lane omitted `--settings` with no error at all. An explicit `null` is
# the JSON spelling of "no value" and still reads as absent; every other value,
# `false` included, now reaches the type check.
lane_json_field() {
  jq -c --argjson i "$1" --arg k "$2" \
    '.lanes[$i] as $l | if ($l | has($k)) and $l[$k] != null then $l[$k] else empty end' "$CONFIG"
}

# Absolute path to a lane's prompt file.
lane_prompt_path() {
  local raw="$1" pdir="$2"
  case "$raw" in
  /* | [A-Za-z]:[\\/]*) printf '%s' "$raw" ;;
  *) printf '%s' "$pdir/$raw" ;;
  esac
}

# --- Lane-stop gate arming (#1784) --------------------------------------------
# The autonomy Stop-hook gate reads its per-session config from a launcher-armed
# record, never the bare environment (see the header). These helpers detect a
# lane's gate request in its settings object, arm the gate through autonomy's
# own helper, and inject the arm id into the lane's --settings.

# Does this lane's settings object request the gate? Any pluginConfigs key for
# the autonomy plugin (bare or marketplace-qualified) with
# options.lane_stop_gate_enabled true (boolean or "true").
lane_requests_stop_gate() {
  jq -e '[ (.pluginConfigs // {}) | to_entries[]
           | select(.key == "autonomy" or (.key | startswith("autonomy@")))
           | .value.options.lane_stop_gate_enabled
           | . == true or . == "true" ] | any' >/dev/null 2>&1 <<<"$1"
}

# String-valued gate option from the lane's settings (last autonomy entry wins);
# empty when absent or non-string.
gate_option_from_settings() {
  jq -r --arg k "$2" '[ (.pluginConfigs // {}) | to_entries[]
      | select(.key == "autonomy" or (.key | startswith("autonomy@")))
      | .value.options[$k] | select(type == "string") ] | last // empty' <<<"$1"
}

# Candidate arm helpers, one path per line. The override wins outright; default
# discovery anchors on THIS script's own install path under plugins/cache and
# globs every installed autonomy version — arming all of them is idempotent
# (same-marketplace versions share one data directory; a second marketplace's
# install keeps its own, and whichever install is active reads its own store).
# Deliberately NOT an env-derived walk (CLAUDE_CONFIG_DIR/HOME): the launcher
# runs inside a session whose project may be the watched repo itself, so a repo
# env block reaches this process — an env-derived path would let it misdirect
# arming into a store the real gate never reads, silently un-gating the lane.
# An unanchored dev checkout without the override finds nothing, and a
# gate-requesting lane then fails closed below.
find_gate_arm_scripts() {
  if [[ -n "$GATE_ARM_SCRIPT_OVERRIDE" ]]; then
    printf '%s\n' "$GATE_ARM_SCRIPT_OVERRIDE"
    return 0
  fi
  local self cache s
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || return 0
  [[ "$self" == */plugins/cache/*/*/* ]] || return 0
  cache="${self%%/plugins/cache/*}/plugins/cache"
  for s in "$cache"/*/autonomy/*/hooks/lane-stop-gate-arm.sh; do
    [[ -f "$s" ]] && printf '%s\n' "$s"
  done
  return 0
}

# A random, filename-safe arm id (the gate validates ^[A-Za-z0-9_-]{8,64}$).
generate_arm_id() {
  local id=""
  if [[ -r /dev/urandom ]] && command -v od >/dev/null 2>&1; then
    id="$(od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n')"
  fi
  [[ -n "$id" ]] || id="$(date +%s 2>/dev/null)$$${RANDOM}${RANDOM}"
  printf '%s' "$id"
}

# Arm the gate for one lane and print the settings JSON with the arm id
# injected. Returns 1 (lane must be skipped — fail closed) when no helper is
# found or ANY found helper fails; helper stdout/stderr goes to stderr so it
# can never leak into the settings this function prints.
#
# EVERY discovered helper must arm. Each install writes into its OWN
# install-derived store, and the launcher cannot tell which install the session
# will load — so one helper succeeding does not prove the ACTIVE one is armed.
# Accepting a partial arm would launch a lane carrying an id its own gate
# resolves to nothing: ungated, with only a stale-arm notice to show for it.
arm_stop_gate() {
  local name="$1" settings="$2" arm_id sentinel marker script found=0 failed=0
  arm_id="$(generate_arm_id)"
  sentinel="$(gate_option_from_settings "$settings" lane_stop_gate_sentinel)"
  marker="$(gate_option_from_settings "$settings" lane_stop_gate_marker)"
  local -a args=(--id "$arm_id" --cwd "$REPO")
  [[ -n "$sentinel" ]] && args+=(--sentinel "$sentinel")
  [[ -n "$marker" ]] && args+=(--marker "$marker")
  while IFS= read -r script; do
    [[ -n "$script" ]] || continue
    found=1
    bash "$script" "${args[@]}" >&2 || failed=1
  done < <(find_gate_arm_scripts)
  if ((found == 0)); then
    # Normally unreachable: validate_launch_inputs preflights helper presence.
    err "lane '$name': lane-stop gate requested but no autonomy gate-arm helper was found (install/update the autonomy plugin, or pass --gate-arm-script) — skipped"
    return 1
  fi
  if ((failed)); then
    err "lane '$name': lane-stop gate arming failed — skipped (launching ungated would defeat the request)"
    return 1
  fi
  jq -c --arg id "$arm_id" \
    '.pluginConfigs |= with_entries(
       if .key == "autonomy" or (.key | startswith("autonomy@"))
       then .value.options.lane_stop_gate_arm_id = $id else . end)' <<<"$settings"
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
# Validates a lane's launch inputs (prompt present + non-empty, effort allowed);
# returns 1 with a per-lane error on the first failure. Split out from launch_lane
# so restart can preflight these BEFORE stopping a running lane — a recoverable
# prompt/effort error must not take a healthy session down and fail to relaunch it.
validate_launch_inputs() {
  local name="$1" effort="$2" prompt_path="$3" settings="${4:-}"
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
  if [[ "$effort" == "ultracode" ]]; then
    local v
    v="$(cli_version)"
    if ! version_at_least "$v" "$ULTRACODE_MIN_VERSION"; then
      err "lane '$name': effort 'ultracode' needs Claude Code >= $ULTRACODE_MIN_VERSION (installed: $v) — skipped"
      return 1
    fi
  fi
  # `settings` must be a JSON object — the launcher passes it verbatim to
  # `claude --settings`, and a string/array/scalar would make the whole session
  # fail to launch with an opaque CLI error instead of a per-lane skip here.
  if [[ -n "$settings" ]] && ! jq -e 'type == "object"' <<<"$settings" >/dev/null 2>&1; then
    err "lane '$name': settings must be a JSON object — skipped"
    return 1
  fi
  # A gate request with no discoverable arm helper is a launch-input error too,
  # and it belongs HERE so restart's preflight catches it BEFORE stopping a
  # healthy running lane (same doctrine as the prompt/effort checks above). A
  # helper that exists but fails at arm time still surfaces in launch_lane.
  # Command substitution, NOT `find_gate_arm_scripts | grep -q .`: under
  # pipefail, grep -q exits on the first line and the producer takes SIGPIPE on
  # its next write, so a machine carrying TWO autonomy installs would read as
  # "no helper found" and refuse to launch a gate-requesting lane.
  if [[ -n "$settings" ]] && lane_requests_stop_gate "$settings" &&
    [[ -z "$(find_gate_arm_scripts)" ]]; then
    err "lane '$name': lane-stop gate requested but no autonomy gate-arm helper was found (install/update the autonomy plugin, or pass --gate-arm-script) — skipped"
    return 1
  fi
}

launch_lane() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" settings="${5:-}"
  validate_launch_inputs "$name" "$effort" "$prompt_path" "$settings" || return 1

  # Arm the lane-stop gate BEFORE launching (fail closed — see header). Under
  # --dry-run nothing is written; the preview line stands in for the arming.
  if [[ -n "$settings" ]] && lane_requests_stop_gate "$settings"; then
    if ((DRY_RUN)); then
      printf 'DRY-RUN: arm lane-stop gate for %s (arm id injected into --settings)\n' "$name"
    else
      settings="$(arm_stop_gate "$name" "$settings")" || return 1
    fi
  fi

  local -a cmd=(claude --bg -n "$name")
  [[ -n "$model" ]] && cmd+=(--model "$model")
  [[ -n "$effort" ]] && cmd+=(--effort "$effort")
  [[ -n "$settings" ]] && cmd+=(--settings "$settings")

  local marker_path
  marker_path="$(launch_commit_marker_path "$name")"

  if ((DRY_RUN)); then
    # Keep the seeded prompt out of the echoed command — show a size placeholder.
    local bytes
    bytes="$(wc -c <"$prompt_path" | tr -d ' ')"
    printf 'DRY-RUN:'
    printf ' %q' "${cmd[@]}"
    printf ' %q\n' "<prompt: $prompt_path (${bytes}B)>"
    printf 'DRY-RUN: write launch-commit marker %s <- %s\n' "$marker_path" "${LAUNCH_COMMIT:-<unresolved>}"
    return 0
  fi

  local prompt
  prompt="$(cat "$prompt_path")"
  cmd+=("$prompt")
  (cd "$REPO" && "${cmd[@]}") || return 1
  # Best-effort: a marker write failure must not fail an already-launched lane.
  write_launch_commit_marker "$marker_path"
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
  # Capture HEAD for the launch-commit marker (#792) regardless of --no-pull —
  # a skipped pull still leaves a well-defined HEAD to record. A pure read
  # (`git rev-parse HEAD`), so it runs under --dry-run too: dry-run's `run`
  # wrapper never actually pulled, so this reports the pre-existing HEAD in
  # the preview line below without writing anything to disk.
  capture_launch_commit
  if ((NO_UPDATE)); then
    info "skip plugin marketplace update (--no-update)"
  else
    info "claude plugin marketplace update"
    run claude plugin marketplace update || rc=1
  fi
  # A skipped step (--no-pull/--no-update) leaves rc=0, so this only fires on an
  # UNEXPECTED failure of a step that actually ran — the intentional-bypass path
  # stays clean. Callers abort the launch on non-zero (see action_start/restart).
  ((rc)) && err "refresh failed (pass --no-pull/--no-update to skip refresh intentionally)"
  return "$rc"
}

# --- Target validation --------------------------------------------------------
# Reject any explicit TARGET_LANES name absent from the config. Called from main
# ahead of action dispatch so an invalid target fails fast (exit 3) BEFORE any
# refresh/mutation runs — matching stop's fail-first DX rather than pulling the
# repo and updating plugins only to reject a misspelled target afterward.
validate_target_lanes() {
  ((${#TARGET_LANES[@]})) || return 0
  local t known
  for t in "${TARGET_LANES[@]}"; do
    known="$(jq -r --arg n "$t" '[.lanes[].name] | index($n) // "no"' "$CONFIG")"
    [[ "$known" != "no" ]] || {
      err "unknown lane '$t' (not in $CONFIG)"
      exit 3
    }
  done
}

# --- Lane iteration helper ----------------------------------------------------
# Runs `callback <name> <model> <effort> <prompt_path> <settings>` for every
# lane, or only the lanes named in TARGET_LANES. Target names are validated up
# front by validate_target_lanes (called from main), so every name here is
# already known.
for_each_lane() {
  local callback="$1" pdir
  pdir="$(resolve_prompt_dir)"
  local count
  count="$(jq -r '.lanes | length' "$CONFIG")"

  local i name model effort prompt_path settings failures=0
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
    settings="$(lane_json_field "$i" settings)"
    # A per-lane callback failure must not abort the sweep (other lanes still
    # get their turn) but must surface in the aggregate exit status.
    "$callback" "$name" "$model" "$effort" "$prompt_path" "$settings" || failures=1
  done
  return "$failures"
}

# --- Actions ------------------------------------------------------------------
_start_one() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" settings="${5:-}" sid
  sid="$(running_session_id "$name")"
  if [[ -n "$sid" ]]; then
    info "  skip $name — already running ($sid)"
    return 0
  fi
  info "  start $name${model:+ --model $model}${effort:+ --effort $effort}${settings:+ --settings <lane config>}"
  launch_lane "$name" "$model" "$effort" "$prompt_path" "$settings"
}

_restart_one() {
  local name="$1" model="$2" effort="$3" prompt_path="$4" settings="${5:-}"
  # Preflight the launch inputs BEFORE stopping: a recoverable prompt/effort
  # error must not take down a healthy running lane we would then fail to relaunch.
  validate_launch_inputs "$name" "$effort" "$prompt_path" "$settings" || return 1
  stop_lane_if_running "$name"
  local s=$?
  # A genuine stop failure (not the benign "was not running", 2) means the old
  # session may still be alive — relaunching would create a second session under
  # the same name, so refuse and surface the failure.
  if [[ $s -ne 0 && $s -ne 2 ]]; then
    err "  $name — stop failed; not relaunching (would duplicate the session name)"
    return 1
  fi
  info "  start $name${model:+ --model $model}${effort:+ --effort $effort}${settings:+ --settings <lane config>}"
  launch_lane "$name" "$model" "$effort" "$prompt_path" "$settings"
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
  # A failed refresh aborts BEFORE launching: never seed lanes from stale
  # repo/plugin state the user did not sign off on (--no-pull/--no-update is the
  # intentional-skip path, which leaves the refresh status 0).
  refresh_repo_and_plugins || return 1
  info "lanes:"
  for_each_lane _start_one || rc=1
  return "$rc"
}

action_restart() {
  local rc=0
  info "== lanes: restart$(lane_scope) =="
  refresh_repo_and_plugins || return 1
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
  # Validate explicit targets up front — before session load and, crucially,
  # before any action's refresh step mutates the repo/plugin state (Item 2).
  validate_target_lanes
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
