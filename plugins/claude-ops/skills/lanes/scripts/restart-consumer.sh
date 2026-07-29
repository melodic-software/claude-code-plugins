#!/usr/bin/env bash
# restart-consumer.sh — consume lane restart-requests and relaunch the lanes.
#
# A loop lane that hits its per-session cycle budget or the /loop seven-day
# expiry writes a restart-request into the `restart_request` field of the
# machine-readable durable-state block on its telemetry comment, then stops
# cleanly — a running loop cannot relaunch itself. Nothing consumed that field,
# so every budget or expiry hit was a terminal manual-restart state. This script
# is that consumer: it reads each configured lane's telemetry and relaunches the
# lanes that asked, through `lane-launcher.sh restart`.
#
# It is meant to run unattended on a schedule owned by the OPERATING SYSTEM
# (Task Scheduler / launchd / systemd --user / cron) rather than by anything
# inside the harness: a watchdog lane is itself a /loop bounded by the same
# seven-day expiry it would remediate, and no in-harness surface survives a
# crashed lane, a harness restart, or a reboot. `print-schedule` emits the exact
# registration commands; registering them is an operator action this script
# never performs.
#
# Usage:
#   restart-consumer.sh [check]           read-only: report what WOULD restart
#   restart-consumer.sh run               relaunch the lanes that asked
#   restart-consumer.sh print-schedule    print the OS scheduler registration
#                                         and removal commands; mutate nothing
# A leading `consume-restarts` token (the skill-level action name SKILL.md
# forwards in $ARGUMENTS) is accepted and ignored.
#
# Options:
#   --config FILE        lane config JSON (same resolution as lane-launcher.sh:
#                        --config -> $CLAUDE_OPS_LANES_CONFIG -> <repo>/.work/lanes.json)
#   --repo DIR           repo root (default: git toplevel of the cwd). Also the
#                        default target repo for the telemetry lookups.
#   --target-repo owner/name
#                        GitHub repo holding the lane telemetry issues
#                        (default: `gh repo view` for --repo). Validated as
#                        owner/repo before any URL interpolation.
#   --lane NAME          restrict to this lane (repeatable). Default: every lane
#                        in the config.
#   --data-dir DIR       base dir for the run ledger; default $CLAUDE_PLUGIN_DATA
#                        env var if set, else ~/.claude/plugins/data/claude-ops.
#                        NOTE: CLAUDE_PLUGIN_DATA reaches hook and MCP/LSP
#                        subprocesses as a real env var but NOT a script a skill
#                        shells out to via the Bash tool (Claude Code
#                        plugins-reference, "Environment variables"), so SKILL.md
#                        passes --data-dir explicitly with the substituted value.
#   --max-restarts N     circuit breaker: at most N relaunch ATTEMPTS per lane
#                        per window — a launch that failed or never came up
#                        spends budget exactly as a successful one does
#                        (default 3). 0 disables the breaker.
#   --window-hours N     the breaker's rolling window in hours (default 24).
#   --interval-minutes N poll interval baked into `print-schedule` (default 15;
#                        1..999, Task Scheduler's MINUTE range).
#   --telemetry-issue N  issue carrying THIS consumer's own status comment.
#                        Default: the issue morning-brief.sh itself reads
#                        (discovered with that reader's own title search), else
#                        the open issue titled exactly
#                        `Lane telemetry: restart-consumer`. Absent -> the run is
#                        recorded in the local ledger only, with a warning.
#   --no-telemetry       skip the consumer's own telemetry upsert entirely.
#   --launcher PATH      lane-launcher.sh to relaunch through (default: the
#                        sibling script next to this one).
#   --agents-json FILE   read the session list from FILE instead of
#                        `claude agents --json` (offline / test injection).
#   --telemetry-json FILE
#                        read lane telemetry from FILE instead of `gh`: a JSON
#                        object mapping lane name -> that issue's comments array,
#                        e.g. {"work":[{"body":"..."}]} (offline / test injection).
#   --now EPOCH          treat EPOCH as the current time (deterministic tests).
#   --dry-run            with `run`: decide and report, but neither relaunch nor
#                        write the ledger or the telemetry comment.
#   --help
#
# Telemetry binding (per lane, every field optional — full contract in
# context/restart-consumer.md):
#   { "name": "work", "prompt": "work.md",
#     "telemetry": { "issue": 42, "marker": "work-items:work-loop",
#                    "repo": "owner/name" } }
#   issue   default: the open issue titled exactly `Lane telemetry: <name>`.
#   marker  default: any comment on that issue carrying the shared sentinel
#           `<!-- claude-ops:lane-telemetry marker=... -->` whose fenced JSON
#           block has a `restart_request` key.
#   repo    default: --target-repo.
#
# THE SHAPE CONSUMED. The producers (work-loop, babysit-loop) document
# `restart_request` only as the field "where a budget or expiry hit records the
# relaunch ask", and emit it as `null` in every published example; no non-null
# shape is specified anywhere. This consumer therefore treats ANY non-null value
# as a request, and additionally reads an optional object form
# {"requested_at":..., "reason":..., "cycle":...} for reporting when one is
# present. It never requires that form.
#
# THE COMMENT IS A SIGNAL, NEVER A TARGET. Lane names, prompts, models, efforts
# and settings come from the operator's LOCAL config; the telemetry comment only
# ever answers "did this configured lane ask?". A comment body is agent- and
# user-writable, so nothing in it is interpolated into a command, a path, or a
# repo — an issue comment can never name a lane the operator has not configured,
# and every value read out of one is parsed by jq, never evaluated.
#
# RELAUNCH PREDICATE — a lane is restarted iff ALL hold:
#   1. it is named in the resolved lane config (and in --lane, if given);
#   2. its telemetry state block parses and `restart_request` is non-null;
#   3. it is NOT currently running (`claude agents --json`, name match plus
#      kind == "background", exactly lane-launcher.sh's own liveness test);
#   4. the circuit breaker has room for it in the rolling window (counted in
#      relaunch attempts, so a lane that keeps failing to come up stops).
# Condition 3 makes the predicate self-clearing: after a relaunch the lane is
# running, so a `restart_request` the relaunched lane has not yet rewritten
# cannot fire a second restart — and the consumer never has to PATCH a telemetry
# comment whose marker another writer identity owns.
#
# The relaunch delegates to `lane-launcher.sh restart <lane>`, which already
# carries that lane's prompt file, --model, --effort and --settings (the
# session-only autonomy-tier override) from the same config, so the lane's
# existing launch shape and autonomy tier are respected by construction rather
# than re-implemented here. `claude respawn` is deliberately NOT used: it
# restarts a background session with the conversation intact
# (https://code.claude.com/docs/en/cli-reference), and a restart-request exists
# precisely because a FRESH context is the only reset a lane gets.
#
# ONE MUTATING RUN AT A TIME. `print-schedule` emits TWO scheduled tasks (a
# poll and an ONLOGON companion), so at logon both fire and Task Scheduler's
# per-task instance policy cannot serialize them. Unsynchronized, two runs read
# the same breaker count, both relaunch, and one lane name ends up with two
# `claude --bg` sessions — lane-launcher.sh's own running-lane guard is
# same-process, and a just-launched session does not appear in
# `claude agents --json` instantly. A `run` therefore holds a mkdir-atomic
# sentinel (`<data-dir>/lanes/<repo-key>/.restart-consumer-lock`, the same idiom
# as the observability prune's `.prune-in-progress`) across the whole
# read -> decide -> relaunch -> append span, released on an EXIT trap. A run that
# cannot take it skips cleanly: exit 0, one `lock-held` flag, no relaunch and no
# telemetry write (the holder owns both). `check` and `--dry-run` mutate nothing
# and take no lock.
#
# OBSERVABILITY. A `run` appends one JSONL row to
# <data-dir>/lanes/<repo-key>/restart-consumer.jsonl per lane whose decision is
# `restarted`, `failed`, `error` or `api-error`; the routine `no-request` / `no-state` /
# `skipped-running` / `breaker-open` ticks are reported but NOT ledgered, so the
# file grows with incidents rather than with the polling interval. `check` is
# read-only and writes nothing. Every `run` also upserts the consumer's own
# sentinel-marked telemetry comment (marker `claude-ops:restart-consumer`)
# carrying the `lane:` / `last-cycle:` / `flags:` fields `morning-brief.sh`
# already parses — so a consumer that stops running surfaces as a STALE lane in
# the morning brief instead of becoming a second silent gap.
#
# Exit codes:
#   0  ok (including "nothing asked for a restart", and a skipped locked tick)
#   3  invalid argument / malformed config
#   4  prerequisite missing (jq, gh, claude), or repo / config unresolved
#   5  at least one lane could not be evaluated or relaunched: a failed relaunch,
#      one that never came up, an open breaker, or a telemetry read that errored

set -uo pipefail

# jq on Git Bash can hand back CRLF-tainted values; strip them once, centrally
# (the same wrapper lane-launcher.sh and telemetry-upsert.sh use).
jq() { command jq "$@" | tr -d '\r'; }

ACTION="check"
CONFIG=""
REPO=""
TARGET_REPO=""
DATA_DIR_OVERRIDE=""
LAUNCHER=""
AGENTS_JSON_FILE=""
TELEMETRY_JSON_FILE=""
TELEMETRY_ISSUE=""
NO_TELEMETRY=0
DRY_RUN=0
MAX_RESTARTS=3
WINDOW_HOURS=24
INTERVAL_MINUTES=15
NOW_EPOCH=""
declare -a TARGET_LANES=()

CONSUMER_MARKER="claude-ops:restart-consumer"
CONSUMER_LANE="restart-consumer"
SENTINEL_PREFIX="<!-- claude-ops:lane-telemetry marker="
TASK_NAME="ClaudeOps Lane Restart Consumer"

err() { printf 'ERROR: %s\n' "$*" >&2; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"; }

check_optarg() {
  [[ -n "${2:-}" && "$2" != -* ]] && return 0
  err "option '$1' requires a non-option argument"
  return 1
}

check_uint() {
  [[ "$2" =~ ^[0-9]+$ ]] && return 0
  err "option '$1' requires a non-negative integer, got: $2"
  return 1
}

parse_args() {
  local seen_action=0
  while (($#)); do
    case "$1" in
    consume-restarts)
      # The skill-level action token (`/claude-ops:lanes consume-restarts ...`):
      # SKILL.md forwards $ARGUMENTS verbatim, so strip it and read the real
      # action (check/run/print-schedule) from the tokens that follow.
      ;;
    check | run | print-schedule)
      ((seen_action)) && {
        err "unexpected extra action: $1"
        exit 3
      }
      ACTION="$1"
      seen_action=1
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
    --target-repo)
      check_optarg "$1" "${2:-}" || exit 3
      TARGET_REPO="$2"
      shift
      ;;
    --target-repo=*) TARGET_REPO="${1#*=}" ;;
    --lane)
      check_optarg "$1" "${2:-}" || exit 3
      TARGET_LANES+=("$2")
      shift
      ;;
    --lane=*) TARGET_LANES+=("${1#*=}") ;;
    --data-dir)
      check_optarg "$1" "${2:-}" || exit 3
      DATA_DIR_OVERRIDE="$2"
      shift
      ;;
    --data-dir=*) DATA_DIR_OVERRIDE="${1#*=}" ;;
    --launcher)
      check_optarg "$1" "${2:-}" || exit 3
      LAUNCHER="$2"
      shift
      ;;
    --launcher=*) LAUNCHER="${1#*=}" ;;
    --agents-json)
      check_optarg "$1" "${2:-}" || exit 3
      AGENTS_JSON_FILE="$2"
      shift
      ;;
    --agents-json=*) AGENTS_JSON_FILE="${1#*=}" ;;
    --telemetry-json)
      check_optarg "$1" "${2:-}" || exit 3
      TELEMETRY_JSON_FILE="$2"
      shift
      ;;
    --telemetry-json=*) TELEMETRY_JSON_FILE="${1#*=}" ;;
    --telemetry-issue)
      check_optarg "$1" "${2:-}" || exit 3
      check_uint "$1" "$2" || exit 3
      TELEMETRY_ISSUE="$2"
      shift
      ;;
    --telemetry-issue=*)
      TELEMETRY_ISSUE="${1#*=}"
      check_uint "--telemetry-issue" "$TELEMETRY_ISSUE" || exit 3
      ;;
    --no-telemetry) NO_TELEMETRY=1 ;;
    --max-restarts)
      check_optarg "$1" "${2:-}" || exit 3
      check_uint "$1" "$2" || exit 3
      MAX_RESTARTS="$2"
      shift
      ;;
    --max-restarts=*)
      MAX_RESTARTS="${1#*=}"
      check_uint "--max-restarts" "$MAX_RESTARTS" || exit 3
      ;;
    --window-hours)
      check_optarg "$1" "${2:-}" || exit 3
      check_uint "$1" "$2" || exit 3
      WINDOW_HOURS="$2"
      shift
      ;;
    --window-hours=*)
      WINDOW_HOURS="${1#*=}"
      check_uint "--window-hours" "$WINDOW_HOURS" || exit 3
      ;;
    --interval-minutes)
      check_optarg "$1" "${2:-}" || exit 3
      check_uint "$1" "$2" || exit 3
      INTERVAL_MINUTES="$2"
      shift
      ;;
    --interval-minutes=*)
      INTERVAL_MINUTES="${1#*=}"
      check_uint "--interval-minutes" "$INTERVAL_MINUTES" || exit 3
      ;;
    --now)
      check_optarg "$1" "${2:-}" || exit 3
      check_uint "$1" "$2" || exit 3
      NOW_EPOCH="$2"
      shift
      ;;
    --now=*)
      NOW_EPOCH="${1#*=}"
      check_uint "--now" "$NOW_EPOCH" || exit 3
      ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      err "unknown option: $1"
      exit 3
      ;;
    *)
      err "unknown action: $1"
      exit 3
      ;;
    esac
    shift
  done
  if ((INTERVAL_MINUTES < 1 || INTERVAL_MINUTES > 999)); then
    err "--interval-minutes must be 1..999 (Task Scheduler's MINUTE range)"
    exit 3
  fi
}

# --- Prerequisites ------------------------------------------------------------
require_jq() {
  command -v jq >/dev/null 2>&1 || {
    err "jq not found (required)"
    exit 4
  }
}

# gh is needed whenever telemetry comes off the network — which a fixture-fed
# check does not, and a fixture-fed `run` does only for its own status comment.
require_gh() {
  if [[ -n "$TELEMETRY_JSON_FILE" ]]; then
    [[ "$ACTION" != "run" || $NO_TELEMETRY -eq 1 || $DRY_RUN -eq 1 ]] && return 0
  fi
  command -v gh >/dev/null 2>&1 || {
    err "gh not found (required unless --telemetry-json covers every read)"
    exit 4
  }
}

require_claude() {
  [[ -n "$AGENTS_JSON_FILE" ]] && return 0
  command -v claude >/dev/null 2>&1 || {
    err "claude CLI not found (required unless --agents-json is supplied)"
    exit 4
  }
}

# --- Resolution ---------------------------------------------------------------
resolve_repo() {
  if [[ -n "$REPO" ]]; then
    [[ -d "$REPO" ]] || {
      err "repo not a directory: $REPO"
      exit 4
    }
    REPO="$(cd "$REPO" && pwd)"
    return 0
  fi
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    err "not inside a git repo; pass --repo DIR"
    exit 4
  }
}

resolve_config() {
  [[ -n "$CONFIG" ]] || CONFIG="${CLAUDE_OPS_LANES_CONFIG:-$REPO/.work/lanes.json}"
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
  ((n > 0)) || {
    err "lane config has no lanes: $CONFIG"
    exit 3
  }
}

# `owner/name`, nothing else — the value reaches a gh API path, so a traversal
# or option-looking value must never get there. The character class admits `.`,
# so dot-only segments (`../evil`) need their own rejection.
valid_repo_slug() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
  local owner="${1%%/*}" name="${1#*/}"
  [[ "$owner" != "." && "$owner" != ".." && "$name" != "." && "$name" != ".." ]]
}

resolve_target_repo() {
  if [[ -z "$TARGET_REPO" ]]; then
    [[ -n "$TELEMETRY_JSON_FILE" && ($NO_TELEMETRY -eq 1 || $ACTION != "run" || $DRY_RUN -eq 1) ]] && return 0
    # `gh repo view` takes an [<owner>/]<repo> argument, never a path: given a
    # directory it parses the leading path segment as a HOST and tries to reach
    # it. The repo is selected by the working directory instead, so run it there.
    TARGET_REPO="$(cd "$REPO" && gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" || TARGET_REPO=""
  fi
  [[ -n "$TARGET_REPO" ]] || {
    err "could not resolve the telemetry repo; pass --target-repo owner/name"
    exit 4
  }
  valid_repo_slug "$TARGET_REPO" || {
    err "invalid --target-repo (want owner/name): $TARGET_REPO"
    exit 3
  }
}

resolve_data_dir() {
  local base="${DATA_DIR_OVERRIDE:-${CLAUDE_PLUGIN_DATA:-$HOME/.claude/plugins/data/claude-ops}}"
  printf '%s/lanes' "${base%/}"
}

# The same injective, canonical-path key lane-launcher.sh uses for its
# launch-commit markers: the data dir is plugin-wide, but a lane name is only
# unique within one repo, so `work` in two checkouts must not share one ledger.
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

ledger_path() { printf '%s/%s/restart-consumer.jsonl' "$(resolve_data_dir)" "$(repo_marker_key)"; }

# The data-dir-relative tail of `ledger_path`. The absolute form is machine-local
# and belongs in this machine's own diagnostics; anything published to the forge
# uses this instead.
ledger_relpath() { printf '%s/restart-consumer.jsonl' "$(repo_marker_key)"; }

# --- Cross-process lock -------------------------------------------------------
LOCK_DIR=""
OWN_LOCK=0
# A run hard-killed mid-flight (reboot, Task Scheduler kill) never reaches its
# EXIT trap, so a lock older than this is treated as abandoned and reclaimed.
# Without that, a 15-minute unattended schedule wedges silently forever — the
# exact failure mode this consumer exists not to become. The bound is far longer
# than a real run, which is bounded by the per-lane confirmation retries.
LOCK_STALE_SECONDS=3600

# shellcheck disable=SC2329  # invoked indirectly: acquire_lock installs it as the EXIT trap
release_lock() {
  ((OWN_LOCK)) || return 0
  OWN_LOCK=0
  rm -f "$LOCK_DIR/acquired-at" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

lock_stamp() {
  local stamp=""
  stamp="$(tr -d '\r\n' <"$LOCK_DIR/acquired-at" 2>/dev/null)" || stamp=""
  [[ "$stamp" =~ ^[0-9]+$ ]] || stamp=0
  printf '%s' "$stamp"
}

# `mkdir` is the atomic arbiter: exactly one process can create the directory, so
# a loser never mutates. The stamp file dates the lock for the abandonment check.
# A loser that finds NO stamp adopts one at `now` rather than reclaiming: the
# holder may have won the mkdir microseconds ago and not written its stamp yet,
# and stealing that lock is the very duplication this guards. Stamping instead
# ages the lock out on a later tick, so a hard-killed run bounds the wedge at
# LOCK_STALE_SECONDS after it is first observed instead of wedging forever.
acquire_lock() {
  local now="$1" stamp
  LOCK_DIR="$(dirname "$(ledger_path)")/.restart-consumer-lock"
  # The data dir does not exist until the first ledger write, and an ENOENT
  # mkdir is indistinguishable from a held lock — so materialize the parent.
  mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null || true
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    stamp="$(lock_stamp)"
    if ((stamp == 0)); then
      printf '%s\n' "$now" >"$LOCK_DIR/acquired-at" 2>/dev/null || true
      return 1
    fi
    ((now - stamp < LOCK_STALE_SECONDS)) && return 1
    warn "reclaiming a lock held since epoch $stamp with no live run to release it: $LOCK_DIR"
    rm -f "$LOCK_DIR/acquired-at" 2>/dev/null || true
    rmdir "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || return 1
  fi
  OWN_LOCK=1
  trap release_lock EXIT
  printf '%s\n' "$now" >"$LOCK_DIR/acquired-at" 2>/dev/null || true
  return 0
}

resolve_launcher() {
  [[ -n "$LAUNCHER" ]] || LAUNCHER="$(dirname "${BASH_SOURCE[0]}")/lane-launcher.sh"
  [[ -f "$LAUNCHER" ]] || {
    err "lane-launcher.sh not found: $LAUNCHER (pass --launcher PATH)"
    exit 4
  }
}

now_epoch() {
  if [[ -n "$NOW_EPOCH" ]]; then printf '%s' "$NOW_EPOCH"; else date -u +%s; fi
}

# RFC3339 UTC from an epoch without `date -d` / `date -r`, neither of which is
# portable across GNU and BSD date (the repo's shell-portability lint bans both).
iso_utc() {
  awk -v e="$1" 'BEGIN {
    days = int(e / 86400); rem = e % 86400
    h = int(rem / 3600); m = int((rem % 3600) / 60); s = rem % 60
    y = 1970
    while (1) {
      leap = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)
      yd = leap ? 366 : 365
      if (days < yd) break
      days -= yd; y++
    }
    leap = ((y % 4 == 0 && y % 100 != 0) || y % 400 == 0)
    split("31 28 31 30 31 30 31 31 30 31 30 31", ml, " ")
    if (leap) ml[2] = 29
    mo = 1
    while (days >= ml[mo]) { days -= ml[mo]; mo++ }
    printf "%04d-%02d-%02dT%02d:%02d:%02dZ", y, mo, days + 1, h, m, s
  }'
}

# A value read out of an untrusted comment that ends up in a report row or a
# public comment body: one line, no table-breaking pipes, bounded length.
sanitize() { printf '%s' "$1" | tr -d '\r\n|`' | cut -c1-200; }

# --- Session list -------------------------------------------------------------
# Loaded once in the main shell so every lane sees one consistent snapshot, and
# so a genuine live-list failure aborts instead of being coerced to an empty list
# — which would make every lane look stopped and relaunch lanes that are alive.
SESSIONS_JSON=""

read_sessions() {
  local raw
  if [[ -n "$AGENTS_JSON_FILE" ]]; then
    [[ -f "$AGENTS_JSON_FILE" ]] || return 1
    raw="$(cat "$AGENTS_JSON_FILE")" || return 1
  else
    raw="$(claude agents --json)" || return 1
  fi
  jq -e 'type == "array"' >/dev/null 2>&1 <<<"$raw" || return 1
  SESSIONS_JSON="$raw"
}

load_sessions() {
  read_sessions || {
    err "could not read the session list (claude agents --json / --agents-json)"
    exit 4
  }
}

lane_is_running() {
  local id
  id="$(jq -r --arg n "$1" \
    '[ .[] | select(.name == $n and .kind == "background") ] | sort_by(.startedAt) | last | .sessionId // empty' \
    <<<"$SESSIONS_JSON")"
  [[ -n "$id" ]]
}

# A just-launched background session does not appear in the list instantly, so
# confirmation retries briefly. Tolerant: a failed re-read leaves the previous
# snapshot in place rather than aborting a run that has already relaunched.
confirm_running() {
  local lane="$1" i
  for i in 1 2 3 4 5; do
    read_sessions || true
    lane_is_running "$lane" && return 0
    [[ -n "$AGENTS_JSON_FILE" ]] && break
    sleep 2
  done
  return 1
}

# --- Config + telemetry reads -------------------------------------------------
lane_field() { jq -r --argjson i "$1" --arg k "$2" '.lanes[$i][$k] // ""' "$CONFIG"; }
lane_telemetry_field() { jq -r --argjson i "$1" --arg k "$2" '(.lanes[$i].telemetry // {})[$k] // ""' "$CONFIG"; }

# `gh issue list --search` is a fuzzy full-text match, so the title is re-checked
# EXACTLY here: a fuzzy hit on some other issue would point the consumer at an
# unrelated comment stream. The search term deliberately omits the colon, which
# GitHub search would read as a qualifier separator.
# Returns 1 — never empty output — when the LIST itself failed, for the same
# reason `lane_comment_bodies` does: empty means "no issue carries this title",
# and coercing an API failure to it would report an unreachable forge as a
# routine `no-telemetry` tick, leaving an unattended consumer apparently healthy
# while it never observes that lane's request. The caller turns a non-zero
# return into its own `api-error` decision.
resolve_issue_by_title() {
  local repo="$1" title="$2" raw
  raw="$(gh issue list --repo "$repo" --state open --limit 100 \
    --search "Lane telemetry in:title" --json number,title 2>/dev/null)" || return 1
  jq -r --arg t "$title" '[ .[] | select(.title == $t) ] | sort_by(.number) | .[0].number // empty' \
    <<<"$raw" 2>/dev/null || return 1
}

# Every comment body on one lane's telemetry issue, as a JSON array of strings.
# Returns 1 — never an empty list — when the read itself failed: "[]" means "the
# issue has no comments", and coercing an API failure to it would report a
# transient `gh` blip as `no-state`, indistinguishable from "the lane did not
# ask". The caller turns a non-zero return into its own `api-error` decision.
lane_comment_bodies() {
  local lane="$1" repo="$2" issue="$3" raw
  if [[ -n "$TELEMETRY_JSON_FILE" ]]; then
    jq -c --arg l "$lane" '[ (.[$l] // [])[] | .body // "" ]' "$TELEMETRY_JSON_FILE"
    return 0
  fi
  raw="$(gh api --paginate "repos/$repo/issues/$issue/comments" -q '.[] | {body}' 2>/dev/null)" || return 1
  printf '%s' "$raw" | jq -s -c '[ .[].body // "" ]' 2>/dev/null || return 1
}

# The first fenced code block that parses as a JSON object carrying a
# `restart_request` key. The body is untrusted text: it is only ever parsed by
# jq, never evaluated, and nothing from it becomes a command argument.
extract_state_block() {
  local line block="" inblock=0
  while IFS= read -r line; do
    if [[ "$line" == '```'* ]]; then
      if ((inblock)); then
        if [[ -n "$block" ]] && jq -e 'type == "object" and has("restart_request")' >/dev/null 2>&1 <<<"$block"; then
          jq -c . <<<"$block"
          return 0
        fi
        block=""
        inblock=0
      else
        inblock=1
        block=""
      fi
      continue
    fi
    ((inblock)) && block+="$line"$'\n'
  done <<<"$1"
  return 1
}

# --- Circuit breaker + ledger -------------------------------------------------
# Counts relaunch ATTEMPTS, not successes: both `restarted` and `failed` spend
# breaker budget. A launcher that exits non-zero, or one that returns success
# while the background lane never appears — the scheduler-spawned Windows hazard
# this consumer confirms rather than trusts — writes `failed`, and counting only
# `restarted` would leave the breaker permanently closed on exactly that failure,
# re-attempting a pull, a marketplace refresh, and a launch on every tick
# forever. `error` and `api-error` are deliberately NOT counted: they are read
# failures that precede any launch, so a transient forge outage must not spend a
# lane's restart budget.
attempts_in_window() {
  local lane="$1" now="$2" ledger cutoff
  ledger="$(ledger_path)"
  [[ -f "$ledger" ]] || {
    printf '0'
    return 0
  }
  cutoff=$((now - WINDOW_HOURS * 3600))
  # FAIL CLOSED. A torn or truncated line makes the whole `jq -s` slurp fail, and
  # returning 0 there would silently restore the full restart budget on exactly
  # the ledger a crashed or racing writer left behind — turning a corrupt file
  # into an unbounded restart loop. Report the budget as spent and say why.
  jq -s -r --arg l "$lane" --argjson c "$cutoff" \
    '[ .[] | select(.lane == $l and (.decision == "restarted" or .decision == "failed") and (.epoch // 0) >= $c) ] | length' \
    "$ledger" 2>/dev/null || {
    warn "run ledger did not parse ($ledger) — treating the breaker as spent for '$lane'; inspect or remove the file"
    printf '%s' "$MAX_RESTARTS"
  }
}

# Ledgered decisions. The routine ticks (`no-request`, `no-state`,
# `skipped-running`, `breaker-open`, `no-telemetry`, `would-restart`) are the
# overwhelming majority on a 15-minute schedule — ledgering them would add ~190
# rows/day forever to a file the breaker re-slurps once per lane per tick. Only
# the incidents are durable; the full per-tick picture is the report and the
# telemetry comment. `restarted` and `failed` are load-bearing: together they ARE
# the breaker's memory, since the breaker bounds attempts rather than successes.
#
# Deliberately filter-on-write rather than prune-on-write: the breaker's verdict
# is a function of the ledger, so a bug in a rewrite-the-whole-file pruner erases
# the record that a lane already burned its budget — the same fail-open the
# corrupt-ledger guard above exists to prevent. Append-only keeps every write a
# single atomic O_APPEND line, and incidents alone are self-limiting.
ledger_decision() {
  case "$1" in
  restarted | failed | error | api-error) return 0 ;;
  *) return 1 ;;
  esac
}

append_ledger() {
  local row="$1" ledger dir
  ((DRY_RUN)) && return 0
  # `check` is documented read-only, and the Verify step in
  # context/restart-consumer.md distinguishes a real `run` from a `check`-only
  # schedule by whether anything was written — a ledger row from a `check` would
  # satisfy that check on the exact failure it exists to catch.
  [[ "$ACTION" == "run" ]] || return 0
  ledger="$(ledger_path)"
  dir="$(dirname "$ledger")"
  if ! mkdir -p "$dir" 2>/dev/null || ! printf '%s\n' "$row" >>"$ledger" 2>/dev/null; then
    warn "run ledger write failed: $ledger"
  fi
}

# --- Report accumulation ------------------------------------------------------
declare -a REPORT_ROWS=()
declare -a FLAGS=()
EXIT_STATUS=0

record() {
  local lane="$1" decision="$2" detail="$3" request="$4" now="$5"
  REPORT_ROWS+=("| $lane | $decision | $detail |")
  ledger_decision "$decision" || return 0
  append_ledger "$(jq -c -n \
    --arg ts "$(iso_utc "$now")" --argjson epoch "$now" --arg lane "$lane" \
    --arg decision "$decision" --arg detail "$detail" --argjson request "$request" \
    '{ts:$ts,epoch:$epoch,lane:$lane,decision:$decision,detail:$detail,request:$request}')"
}

fail_lane() {
  FLAGS+=("$1")
  EXIT_STATUS="$2"
}

# --- Per-lane evaluation ------------------------------------------------------
lane_selected() {
  ((${#TARGET_LANES[@]})) || return 0
  local t
  for t in "${TARGET_LANES[@]}"; do [[ "$t" == "$1" ]] && return 0; done
  return 1
}

process_lane() {
  local idx="$1" now="$2"
  local lane repo issue marker bodies body state request reason used n i found=0
  lane="$(lane_field "$idx" name)"
  [[ -n "$lane" ]] || return 0
  lane_selected "$lane" || return 0

  repo="$(lane_telemetry_field "$idx" repo)"
  [[ -n "$repo" ]] || repo="$TARGET_REPO"
  if [[ -n "$repo" ]] && ! valid_repo_slug "$repo"; then
    record "$lane" "error" "invalid telemetry repo in config: $(sanitize "$repo")" null "$now"
    fail_lane "config-error($lane)" 3
    return 0
  fi

  issue="$(lane_telemetry_field "$idx" issue)"
  if [[ -n "$issue" && ! "$issue" =~ ^[0-9]+$ ]]; then
    record "$lane" "error" "telemetry.issue is not a number: $(sanitize "$issue")" null "$now"
    fail_lane "config-error($lane)" 3
    return 0
  fi
  if [[ -z "$issue" && -z "$TELEMETRY_JSON_FILE" ]]; then
    if ! issue="$(resolve_issue_by_title "$repo" "Lane telemetry: $lane")"; then
      record "$lane" "api-error" "could not list open issues on $repo (gh issue list); telemetry issue unresolved, not restarting" null "$now"
      fail_lane "api-error($lane)" 5
      return 0
    fi
    [[ -n "$issue" ]] || {
      record "$lane" "no-telemetry" "no open issue titled 'Lane telemetry: $lane'; bind lanes[].telemetry.issue" null "$now"
      return 0
    }
  fi

  marker="$(lane_telemetry_field "$idx" marker)"
  if ! bodies="$(lane_comment_bodies "$lane" "$repo" "$issue")"; then
    record "$lane" "api-error" "could not read the comments on #$issue (gh api); state unknown, not restarting" null "$now"
    fail_lane "api-error($lane)" 5
    return 0
  fi
  n="$(jq -r 'length' <<<"$bodies" 2>/dev/null)" || n=0
  request="null"
  for ((i = 0; i < n; i++)); do
    body="$(jq -r ".[$i]" <<<"$bodies")"
    [[ "$body" == *"$SENTINEL_PREFIX"* ]] || continue
    [[ -z "$marker" || "$body" == *"$SENTINEL_PREFIX$marker "* ]] || continue
    state="$(extract_state_block "$body")" || continue
    found=1
    request="$(jq -c '.restart_request' <<<"$state")"
    break
  done

  if ((!found)); then
    record "$lane" "no-state" "no sentinel comment with a parseable state block on #$issue" null "$now"
    return 0
  fi
  if [[ "$request" == "null" ]]; then
    record "$lane" "no-request" "restart_request is null" null "$now"
    return 0
  fi

  # The optional object form is read for the REPORT only; the predicate stays
  # "non-null", which is the shape the producers actually emit.
  reason="$(sanitize "$(jq -r '
    if type == "object"
    then (.reason // "unspecified" | tostring)
         + (if .requested_at then " @ " + (.requested_at | tostring) else "" end)
    else tostring end' <<<"$request")")"

  if lane_is_running "$lane"; then
    record "$lane" "skipped-running" "lane already running; stale request ($reason)" "$request" "$now"
    return 0
  fi

  used="$(attempts_in_window "$lane" "$now")"
  if ((MAX_RESTARTS > 0 && used >= MAX_RESTARTS)); then
    record "$lane" "breaker-open" "$used relaunch attempts in the last ${WINDOW_HOURS}h (max $MAX_RESTARTS); not restarting" "$request" "$now"
    fail_lane "breaker-open($lane)" 5
    return 0
  fi

  if [[ "$ACTION" != "run" ]] || ((DRY_RUN)); then
    record "$lane" "would-restart" "$reason" "$request" "$now"
    return 0
  fi

  info "restarting lane '$lane' ($reason)"
  local -a launch=(restart "$lane" --config "$CONFIG" --repo "$REPO")
  [[ -n "$DATA_DIR_OVERRIDE" ]] && launch+=(--data-dir "$DATA_DIR_OVERRIDE")
  if ! bash "$LAUNCHER" "${launch[@]}"; then
    record "$lane" "failed" "lane-launcher.sh restart exited non-zero" "$request" "$now"
    fail_lane "restart-failed($lane)" 5
    return 0
  fi

  # Confirm rather than trust: whether a `claude --bg` session launched from a
  # scheduler-spawned parent survives that parent is unverified on Windows, so a
  # relaunch that does not come up must be loud here, not silent.
  if confirm_running "$lane"; then
    record "$lane" "restarted" "$reason" "$request" "$now"
  else
    record "$lane" "failed" "relaunched but the lane never appeared in the session list" "$request" "$now"
    fail_lane "restart-unconfirmed($lane)" 5
  fi
}

# --- The consumer's own telemetry --------------------------------------------
upsert_own_telemetry() {
  local now="$1" issue body flagstr row upsert
  ((NO_TELEMETRY)) && return 0
  ((DRY_RUN)) && return 0
  [[ "$ACTION" == "run" ]] || return 0

  issue="$TELEMETRY_ISSUE"
  # Default: the issue morning-brief.sh itself reads, discovered with that
  # reader's own title search — landing the comment there is what makes the
  # consumer visible in the brief with no reader change. Fall back to an exact
  # `Lane telemetry: restart-consumer` title (local convention; the brief only
  # reads it when pinned to it via its own --telemetry-issue).
  #
  # The search term and the selector below must stay BYTE-IDENTICAL to
  # morning-brief.sh's resolve_telemetry_issue: they are what make both tools
  # resolve the SAME issue, and a silent divergence would post this consumer's
  # status where the brief never looks. Not factored into a shared source (the
  # two skills are independently installable), so restart-consumer.test.sh
  # asserts the literal appears verbatim in both files.
  [[ -n "$issue" ]] || issue="$(gh issue list --repo "$TARGET_REPO" --state open \
    --search "loop-lane telemetry running per-lane status in:title" \
    --json number 2>/dev/null | jq -r 'sort_by(.number) | .[0].number // empty')"
  [[ -n "$issue" ]] || issue="$(resolve_issue_by_title "$TARGET_REPO" "Lane telemetry: $CONSUMER_LANE")"
  [[ -n "$issue" ]] || {
    warn "no telemetry issue found on $TARGET_REPO (neither the morning-brief title search nor 'Lane telemetry: $CONSUMER_LANE') — this run is in the local ledger only. Pass --telemetry-issue N (ideally the issue the morning brief reads) so a consumer that stops running shows up as STALE in the morning brief."
    return 0
  }

  flagstr="none"
  if ((${#FLAGS[@]})); then
    flagstr="$(printf '%s, ' "${FLAGS[@]}")"
    flagstr="${flagstr%, }"
  fi

  body="lane: $CONSUMER_LANE
last-cycle: $(iso_utc "$now")
flags: $flagstr

| lane | decision | detail |
|---|---|---|"
  for row in "${REPORT_ROWS[@]}"; do body+="
$row"; done
  # The ledger path is machine-local and this comment is as visible as the
  # repository is: a default path carries the operator's home-directory user
  # name, and a --data-dir override can carry internal host or organization
  # names. Name the file relative to whatever data dir the reader's own machine
  # resolves, never the absolute path this run used.
  body+="

Run ledger: \`<data-dir>/$(ledger_relpath)\` on the machine running this consumer."

  upsert="$(dirname "${BASH_SOURCE[0]}")/telemetry-upsert.sh"
  [[ -f "$upsert" ]] || {
    warn "telemetry-upsert.sh not found next to this script; skipping the status comment"
    return 0
  }
  printf '%s\n' "$body" |
    bash "$upsert" --issue "$issue" --marker "$CONSUMER_MARKER" --body-file - --repo "$TARGET_REPO" ||
    warn "the consumer's telemetry upsert failed (the restarts themselves are unaffected)"
}

# --- print-schedule -----------------------------------------------------------
action_print_schedule() {
  local self claude_bin run_cmd win_repo win_claude data_dir
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  # The offline form's --data-dir must be COPY-PASTEABLE, because the warning
  # under it is that a second data dir splits the breaker ledger. When the caller
  # passed one, echo it back; otherwise keep the placeholder that says what to
  # substitute.
  data_dir="${DATA_DIR_OVERRIDE:-<the CLAUDE_PLUGIN_DATA dir skill runs use>}"
  claude_bin="$(command -v claude 2>/dev/null)" || claude_bin="claude"
  # Windows-form paths for the schtasks payload: cmd.exe cannot use the
  # MSYS-form paths Git Bash resolves (`/c/...`), and cygpath -w also restores
  # the real claude.exe name behind the extensionless shim `command -v` finds.
  win_repo="$(cygpath -w "$REPO" 2>/dev/null)" || win_repo="$REPO"
  win_claude="$(cygpath -w "$claude_bin" 2>/dev/null)" || win_claude="$claude_bin"
  # `run` is load-bearing: the script's default action is the read-only
  # `check`, so a schedule registered without `run` would report forever and
  # never relaunch anything.
  run_cmd='claude -p "/claude-ops:lanes consume-restarts run" --output-format text'

  cat <<EOF
Registering the schedule is an OPERATOR action — this script never performs it.
Run one of the commands below yourself.

The reader is driven by an OS-level scheduler on purpose: it exists to survive
exactly the cases nothing inside the harness can — a crashed lane, a harness
restart, a reboot. Poll interval: every ${INTERVAL_MINUTES} minutes.

Repo:   $REPO
claude: $claude_bin
Reader: $run_cmd

== Windows — Task Scheduler (current user, no elevation, no stored password) ==

  Run each schtasks line below from cmd.exe, on one line as printed (the
  ClaudeCodeOtelPrune precedent's form; %USERNAME% and the \\" escaping are
  cmd.exe syntax). NOT from Git Bash: MSYS path conversion rewrites /-style
  options — 'schtasks /Query' becomes an invalid 'C:/Program Files/Git/Query'.

schtasks /Create /TN "$TASK_NAME" /SC MINUTE /MO ${INTERVAL_MINUTES} /F /RU "%USERNAME%" /IT /RL LIMITED /TR "cmd /c cd /d \"$win_repo\" && \"$win_claude\" -p \"/claude-ops:lanes consume-restarts run\" --output-format text"

  /IT runs the task only while that user is logged on, so the CLI reads the
  credentials already in the user profile: no stored password, no elevation.
  schtasks has no working-directory flag, hence the 'cmd /c cd /d' wrapper.

  Cold start after a reboot — add a logon trigger alongside the poll:

schtasks /Create /TN "$TASK_NAME (logon)" /SC ONLOGON /F /RU "%USERNAME%" /IT /RL LIMITED /TR "cmd /c cd /d \"$win_repo\" && \"$win_claude\" -p \"/claude-ops:lanes consume-restarts run\" --output-format text"

  Remove both (also from cmd.exe):

schtasks /Delete /TN "$TASK_NAME" /F
schtasks /Delete /TN "$TASK_NAME (logon)" /F

== macOS (launchd user agent) / Linux (systemd --user timer, or cron) ==

  Same command on the same interval. cron form:

*/${INTERVAL_MINUTES} * * * * cd '$REPO' && '$claude_bin' -p '/claude-ops:lanes consume-restarts run' --output-format text

== Offline variant (no model turn) ==

  The reader is a deterministic script; the headless 'claude -p' wrapper only
  routes through the skill. Schedule this where a model turn is unwanted:

bash '$self' run --repo '$REPO' --data-dir '$data_dir'

  --data-dir matters here: skill-invoked runs pass the resolved
  CLAUDE_PLUGIN_DATA directory explicitly, and this form's env-var fallback
  can resolve elsewhere — two directories would split the circuit-breaker
  ledger and widen the effective restart budget.
EOF
}

# --- Main ---------------------------------------------------------------------
main() {
  parse_args "$@"
  require_jq
  resolve_repo

  if [[ "$ACTION" == "print-schedule" ]]; then
    action_print_schedule
    exit 0
  fi

  resolve_config
  resolve_target_repo
  resolve_launcher
  require_gh
  require_claude
  load_sessions

  local now n i
  now="$(now_epoch)"

  # Held across the whole read -> decide -> relaunch -> append span, and across
  # the telemetry upsert, so a losing tick writes nothing at all. Only a real
  # `run` mutates, so only a real `run` contends.
  if [[ "$ACTION" == "run" ]] && ((!DRY_RUN)) && ! acquire_lock "$now"; then
    warn "another restart-consumer run holds the lock ($LOCK_DIR) — skipping this tick"
    info "restart-consumer: $ACTION on ${TARGET_REPO:-<fixtures>} at $(iso_utc "$now")"
    info "| lane | decision | detail |"
    info "|---|---|---|"
    info "| (none) | lock-held | another run holds $LOCK_DIR; skipped |"
    exit 0
  fi

  n="$(jq -r '(.lanes // []) | length' "$CONFIG")"
  for ((i = 0; i < n; i++)); do process_lane "$i" "$now"; done

  info "restart-consumer: $ACTION on ${TARGET_REPO:-<fixtures>} at $(iso_utc "$now")"
  info "| lane | decision | detail |"
  info "|---|---|---|"
  if ((${#REPORT_ROWS[@]})); then
    printf '%s\n' "${REPORT_ROWS[@]}"
  else
    info "| (none) | no-lanes | no configured lane matched |"
  fi

  upsert_own_telemetry "$now"
  exit "$EXIT_STATUS"
}

main "$@"
