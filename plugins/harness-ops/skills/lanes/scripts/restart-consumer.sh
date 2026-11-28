#!/usr/bin/env bash
# Exit codes:
#   0  ok (including "nothing asked for a restart", and a skipped locked tick)
#   3  invalid argument / malformed config
#   4  prerequisite missing (jq, gh, claude), or repo / config / write identity
#      unresolved, or the lock store is unusable (a held lock is not that: it
#      exits 0)
#   5  at least one lane could not be evaluated or relaunched: a failed relaunch,
#      one that never came up, an open breaker, or a telemetry read that errored

set -uo pipefail

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
APP_SLUG=""
WRITE_IDENTITY=""
NO_TELEMETRY=0
DRY_RUN=0
MAX_RESTARTS=3
WINDOW_HOURS=24
INTERVAL_MINUTES=15
NOW_EPOCH=""
declare -a TARGET_LANES=()

CONSUMER_MARKER="harness-ops:restart-consumer"
CONSUMER_LANE="restart-consumer"
SENTINEL_PREFIX="<!-- harness-ops:lane-telemetry marker="
TASK_NAME="HarnessOps Lane Restart Consumer"
PERMISSION_PROMPTS_MIN_VERSION="2.1.259"

err() { printf 'ERROR: %s\n' "$*" >&2; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

usage() {
  cat <<'EOF'
restart-consumer.sh: consume lane restart-requests and relaunch the lanes that asked.
Contract (relaunch predicate, write identity, telemetry binding): context/restart-consumer.md.

Usage:
  restart-consumer.sh [check]           read-only: report what WOULD restart
  restart-consumer.sh run               relaunch the lanes that asked
  restart-consumer.sh print-schedule    print the OS scheduler registration and removal commands
A leading `consume-restarts` token is accepted and ignored.

  --config FILE           lane config JSON (same resolution as lane-launcher.sh)
  --repo DIR              repo root (default: git toplevel of the cwd)
  --target-repo owner/name  repo holding the lane telemetry issues (default: `gh repo view`)
  --lane NAME             restrict to this lane; repeatable (default: every configured lane)
  --data-dir DIR          base dir for the run ledger (default: harness-ops plugin data)
  --max-restarts N        relaunch attempts per lane per window (default 3; 0 disables)
  --window-hours N        the breaker's rolling window in hours (default 24)
  --interval-minutes N    poll interval baked into `print-schedule` (default 15; 1..999)
  --telemetry-issue N     issue carrying this consumer's own status comment
  --no-telemetry          skip the consumer's own telemetry upsert
  --launcher PATH         lane-launcher.sh to relaunch through (default: the sibling script)
  --agents-json FILE      session list instead of `claude agents --json` (tests)
  --app-slug SLUG         GitHub App whose installation token gh runs under
  --telemetry-json FILE   lane telemetry instead of `gh` (tests)
  --now EPOCH             treat EPOCH as the current time (tests)
  --dry-run               with `run`: decide and report; relaunch and write nothing
  --help

Exit codes:
  0  ok (including "nothing asked for a restart", and a skipped locked tick)
  3  invalid argument / malformed config
  4  prerequisite missing (jq, gh, claude), or repo / config / write identity
     unresolved, or the lock store is unusable
  5  at least one lane could not be evaluated or relaunched
EOF
}

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

set_opt() {
  case "$1" in
  --config) CONFIG="$2" ;;
  --repo) REPO="$2" ;;
  --target-repo) TARGET_REPO="$2" ;;
  --lane) TARGET_LANES+=("$2") ;;
  --data-dir) DATA_DIR_OVERRIDE="$2" ;;
  --launcher) LAUNCHER="$2" ;;
  --agents-json) AGENTS_JSON_FILE="$2" ;;
  --telemetry-json) TELEMETRY_JSON_FILE="$2" ;;
  *)
    check_uint "$1" "$2" || exit 3
    case "$1" in
    --telemetry-issue) TELEMETRY_ISSUE="$2" ;;
    --max-restarts) MAX_RESTARTS="$2" ;;
    --window-hours) WINDOW_HOURS="$2" ;;
    --interval-minutes) INTERVAL_MINUTES="$2" ;;
    --now) NOW_EPOCH="$2" ;;
    *) ;;
    esac
    ;;
  esac
}

parse_args() {
  local seen_action=0
  while (($#)); do
    case "$1" in
    consume-restarts)
      ;;
    check | run | print-schedule)
      ((seen_action)) && {
        err "unexpected extra action: $1"
        exit 3
      }
      ACTION="$1"
      seen_action=1
      ;;
    --config | --repo | --target-repo | --lane | --data-dir | --launcher | --agents-json | \
      --telemetry-json | --telemetry-issue | --max-restarts | --window-hours | --interval-minutes | --now)
      check_optarg "$1" "${2:-}" || exit 3
      set_opt "$1" "$2"
      shift
      ;;
    --config=* | --repo=* | --target-repo=* | --lane=* | --data-dir=* | --launcher=* | --agents-json=* | \
      --telemetry-json=* | --telemetry-issue=* | --max-restarts=* | --window-hours=* | --interval-minutes=* | --now=*)
      set_opt "${1%%=*}" "${1#*=}"
      ;;
    --app-slug)
      if (($# < 2)) || [[ "$2" == -* ]]; then
        err "option '$1' requires a non-option argument"
        exit 3
      fi
      APP_SLUG="$2"
      shift
      ;;
    --app-slug=*) APP_SLUG="${1#*=}" ;;
    --no-telemetry) NO_TELEMETRY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      err "unknown option: $1 (see --help)"
      exit 3
      ;;
    *)
      err "unknown action: $1 (want: check run print-schedule)"
      exit 3
      ;;
    esac
    shift
  done
  [[ "$APP_SLUG" == "\${user_config."* ]] && APP_SLUG=""
  if [[ -n "$APP_SLUG" && ! "$APP_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    err "--app-slug must be a GitHub App slug, got: $APP_SLUG"
    exit 3
  fi
  if ((INTERVAL_MINUTES < 1 || INTERVAL_MINUTES > 999)); then
    err "--interval-minutes must be 1..999 (Task Scheduler's MINUTE range)"
    exit 3
  fi
}

require_jq() {
  command -v jq >/dev/null 2>&1 || {
    err "jq not found (required)"
    exit 4
  }
}

telemetry_fully_fixtured() {
  [[ -n "$TELEMETRY_JSON_FILE" ]] || return 1
  [[ "$ACTION" != "run" ]] || ((NO_TELEMETRY)) || ((DRY_RUN))
}

require_gh() {
  telemetry_fully_fixtured && return 0
  command -v gh >/dev/null 2>&1 || {
    err "gh not found (required unless --telemetry-json covers every read)"
    exit 4
  }
}

resolve_write_identity() {
  local who=""
  if who="$(gh api user --jq '.login + " " + .type' 2>/dev/null | tr -d '\r')" && [[ "$who" == *" User" ]]; then
    WRITE_IDENTITY="${who% User}"
  elif [[ -n "$APP_SLUG" ]]; then
    WRITE_IDENTITY="${APP_SLUG}[bot]"
  elif [[ "$who" == *" Bot" ]]; then
    WRITE_IDENTITY="${who% Bot}"
    [[ "$WRITE_IDENTITY" == *"[bot]" ]] || WRITE_IDENTITY+="[bot]"
  else
    return 1
  fi
  [[ "$WRITE_IDENTITY" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*(\[bot\])?$ ]]
}

require_write_identity() {
  [[ -n "$TELEMETRY_JSON_FILE" ]] && return 0
  resolve_write_identity && return 0
  err "cannot resolve the lanes' write identity (gh api user failed or reported no User); pass --app-slug under an App token. No lane was read or relaunched."
  exit 4
}

require_claude() {
  [[ -n "$AGENTS_JSON_FILE" ]] && return 0
  command -v claude >/dev/null 2>&1 || {
    err "claude CLI not found (required unless --agents-json is supplied)"
    exit 4
  }
}

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
  if [[ -z "$CONFIG" ]]; then
    CONFIG="${HARNESS_OPS_LANES_CONFIG:-$REPO/.work/lanes/lanes.json}"
    if [[ -z "${HARNESS_OPS_LANES_CONFIG:-}" && ! -f "$CONFIG" && -f "$REPO/.work/lanes.json" ]]; then
      warn "reading the pre-move lane config at $REPO/.work/lanes.json"
      warn "  move it (and the lane prompt files) to $REPO/.work/lanes/ — this fallback is temporary"
      CONFIG="$REPO/.work/lanes.json"
    fi
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
  ((n > 0)) || {
    err "lane config has no lanes: $CONFIG"
    exit 3
  }
}

valid_repo_slug() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 1
  local owner="${1%%/*}" name="${1#*/}"
  [[ "$owner" != "." && "$owner" != ".." && "$name" != "." && "$name" != ".." ]]
}

resolve_target_repo() {
  if [[ -z "$TARGET_REPO" ]]; then
    telemetry_fully_fixtured && return 0
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
  local base="$DATA_DIR_OVERRIDE" seg="${CLAUDE_PLUGIN_DATA:-}"
  if [[ -z "$base" ]]; then
    seg="${seg%[/\\]}"
    seg="${seg##*[/\\]}"
    if [[ "$seg" == harness-ops || "$seg" == harness-ops-* ]]; then
      base="$CLAUDE_PLUGIN_DATA"
    else
      base="$HOME/.claude/plugins/data/harness-ops"
    fi
  fi
  printf '%s/lanes' "${base%/}"
}

REPO_MARKER_KEY=""
repo_marker_key() {
  if [[ -z "$REPO_MARKER_KEY" ]]; then
    local top
    top="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || top=""
    [[ -n "$top" ]] || top="$REPO"
    REPO_MARKER_KEY="$(printf '%s' "$top" | git -C "$REPO" hash-object --stdin 2>/dev/null)"
    [[ -n "$REPO_MARKER_KEY" ]] || REPO_MARKER_KEY="unkeyed"
  fi
  printf '%s' "$REPO_MARKER_KEY"
}

ledger_relpath() { printf '%s/restart-consumer.jsonl' "$(repo_marker_key)"; }

ledger_path() { printf '%s/%s' "$(resolve_data_dir)" "$(ledger_relpath)"; }

LOCK_DIR=""
OWN_LOCK=0
LOCK_STALE_SECONDS=3600

remove_lock_dir() {
  rm -f "$LOCK_DIR/acquired-at" "$LOCK_DIR/owner-pid" "$LOCK_DIR/boot-id" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

# shellcheck disable=SC2329  # invoked indirectly: acquire_lock installs it as the EXIT trap
release_lock() {
  ((OWN_LOCK)) || return 0
  OWN_LOCK=0
  remove_lock_dir
}

lock_uint_file() {
  local value=""
  value="$(tr -d '\r\n' <"$1" 2>/dev/null)" || value=""
  [[ "$value" =~ ^[0-9]+$ ]] || value=0
  printf '%s' "$value"
}

lock_stamp() { lock_uint_file "$LOCK_DIR/acquired-at"; }
lock_owner_pid() { lock_uint_file "$LOCK_DIR/owner-pid"; }

boot_identity() {
  [[ -n "${RESTART_CONSUMER_FAKE_BOOT_ID-}" ]] && {
    printf '%s' "$RESTART_CONSUMER_FAKE_BOOT_ID"
    return 0
  }
  [[ -r /proc/sys/kernel/random/boot_id ]] && {
    tr -d '\r\n' </proc/sys/kernel/random/boot_id
    return 0
  }
  return 1
}

lock_boot_id() { tr -d '\r\n' <"$LOCK_DIR/boot-id" 2>/dev/null || printf ''; }

LOCK_HARD_STALE_SECONDS=86400

lock_owner_alive() {
  local pid="$1" age="$2" recorded_boot current_boot
  ((pid > 0)) || return 1

  recorded_boot="$(lock_boot_id)"
  if current_boot="$(boot_identity)" && [[ -n "$recorded_boot" ]]; then
    [[ "$recorded_boot" == "$current_boot" ]] || return 1
  else
    ((age >= LOCK_HARD_STALE_SECONDS)) && return 1
  fi

  if [[ -n "${RESTART_CONSUMER_FAKE_ALIVE_PIDS+set}" ]]; then
    [[ " $RESTART_CONSUMER_FAKE_ALIVE_PIDS " == *" $pid "* ]]
    return
  fi
  kill -0 "$pid" 2>/dev/null
}

take_lock_dir() {
  mkdir "$LOCK_DIR" 2>/dev/null &&
    (set -o noclobber && printf '%s\n' "$$" >"$LOCK_DIR/owner-pid") 2>/dev/null
}

acquire_lock() {
  local now="$1" stamp pid parent boot_now
  LOCK_DIR="$(dirname "$(ledger_path)")/.restart-consumer-lock"
  parent="$(dirname "$LOCK_DIR")"
  if ! mkdir -p "$parent" 2>/dev/null && [[ ! -d "$parent" ]]; then
    err "cannot create the lock directory's parent: $parent"
    return 2
  fi
  if ! take_lock_dir; then
    if [[ ! -d "$LOCK_DIR" ]]; then
      err "cannot create the lock directory: $LOCK_DIR"
      return 2
    fi
    stamp="$(lock_stamp)"
    pid="$(lock_owner_pid)"
    if ((stamp == 0)); then
      write_lock_file "$LOCK_DIR/acquired-at" "$now" || return 2
      return 1
    fi
    ((now - stamp < LOCK_STALE_SECONDS)) && return 1
    if lock_owner_alive "$pid" "$((now - stamp))"; then
      warn "lock held since epoch $stamp is past the stale bound but its owner (pid $pid) is alive on the same boot; leaving it held: $LOCK_DIR"
      return 1
    fi
    warn "reclaiming a lock held since epoch $stamp with no live run to release it: $LOCK_DIR"
    remove_lock_dir
    take_lock_dir || return 1
  fi
  OWN_LOCK=1
  trap release_lock EXIT
  write_lock_file "$LOCK_DIR/acquired-at" "$now" || return 2
  write_lock_file "$LOCK_DIR/owner-pid" "$$" || return 2
  if boot_now="$(boot_identity)"; then
    write_lock_file "$LOCK_DIR/boot-id" "$boot_now" || return 2
  fi
  return 0
}

write_lock_file() {
  local path="$1" value="$2"
  printf '%s\n' "$value" >"$path" 2>/dev/null && return 0
  err "cannot write the lock file: $path"
  return 1
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

sanitize() { printf '%s' "$1" | tr -d '\r\n|`' | cut -c1-200; }

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

lane_field() { jq -r --argjson i "$1" --arg k "$2" '.lanes[$i][$k] // ""' "$CONFIG"; }
lane_telemetry_field() { jq -r --argjson i "$1" --arg k "$2" '(.lanes[$i].telemetry // {})[$k] // ""' "$CONFIG"; }

lane_comment_marker_matches() {
  local body="$1" marker="$2" instance="$3"
  [[ -n "$marker" ]] || return 0
  case "$marker" in
  *@*) [[ "$body" == *"$SENTINEL_PREFIX$marker "* ]] ;;
  *)
    if [[ -n "$instance" ]]; then
      [[ "$body" == *"$SENTINEL_PREFIX$marker@$instance "* ]]
    else
      [[ "$body" == *"$SENTINEL_PREFIX$marker "* || "$body" == *"$SENTINEL_PREFIX$marker@"* ]]
    fi
    ;;
  esac
}

resolve_issue_by_title() {
  local repo="$1" title="$2" author="${3:-}" raw foreign
  raw="$(gh api --method GET search/issues -f per_page=100 \
    -f q="repo:$repo is:issue is:open Lane telemetry in:title" 2>/dev/null)" || return 1
  jq -e '.incomplete_results == false' <<<"$raw" >/dev/null 2>&1 || return 1
  foreign="$(jq -r --arg t "$title" --arg me "$WRITE_IDENTITY" --arg a "$author" \
    '[ .items[] | select(.title == $t and .user.login != $me and ($a == "" or .user.login != $a))
       | "#\(.number) by \(.user.login // "unknown")" ] | join(", ")' <<<"$raw" 2>/dev/null)" || return 1
  [[ -z "$foreign" ]] || warn "skipped '$title' issues not opened by the write identity: $(sanitize "$foreign")"
  jq -r --arg t "$title" --arg me "$WRITE_IDENTITY" --arg a "$author" \
    '[ .items[] | select(.title == $t and (.user.login == $me or ($a != "" and .user.login == $a))) ]
     | sort_by(.number) | .[0].number // empty' <<<"$raw" 2>/dev/null || return 1
}

lane_comment_bodies() {
  local lane="$1" repo="$2" issue="$3" raw
  if [[ -n "$TELEMETRY_JSON_FILE" ]]; then
    jq -c --arg l "$lane" '[ (.[$l] // [])[] | .body // "" ]' "$TELEMETRY_JSON_FILE" 2>/dev/null || return 1
    return 0
  fi
  raw="$(gh api --paginate "repos/$repo/issues/$issue/comments?per_page=100" \
    -q '.[] | {body, login: .user.login}' 2>/dev/null)" || return 1
  printf '%s' "$raw" | jq -s -c --arg me "$WRITE_IDENTITY" \
    '[ .[] | select(.login == $me) | .body // "" ]' 2>/dev/null || return 1
}

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

attempts_in_window() {
  local lane="$1" now="$2" ledger cutoff
  ledger="$(ledger_path)"
  [[ -f "$ledger" ]] || {
    printf '0'
    return 0
  }
  cutoff=$((now - WINDOW_HOURS * 3600))
  jq -s -r --arg l "$lane" --argjson c "$cutoff" \
    '[ .[] | select(.lane == $l and (.decision == "restarted" or .decision == "failed") and (.epoch // 0) >= $c) ] | length' \
    "$ledger" 2>/dev/null || {
    warn "run ledger did not parse ($ledger) — treating the breaker as spent for '$lane'; inspect or remove the file"
    printf '%s' "$MAX_RESTARTS"
  }
}

ledger_decision() {
  case "$1" in
  restarted | failed | error | api-error) return 0 ;;
  *) return 1 ;;
  esac
}

ledger_writable() {
  local ledger dir
  ((DRY_RUN)) && return 0
  [[ "$ACTION" == "run" ]] || return 0
  ledger="$(ledger_path)"
  dir="$(dirname "$ledger")"
  mkdir -p "$dir" 2>/dev/null || [[ -d "$dir" ]] || return 1
  (: >>"$ledger") 2>/dev/null || return 1
}

append_ledger() {
  local row="$1" ledger dir
  ((DRY_RUN)) && return 0
  [[ "$ACTION" == "run" ]] || return 0
  ledger="$(ledger_path)"
  dir="$(dirname "$ledger")"
  if ! mkdir -p "$dir" 2>/dev/null || ! (printf '%s\n' "$row" >>"$ledger") 2>/dev/null; then
    err "run ledger write failed: $ledger"
    return 1
  fi
}

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
    '{ts:$ts,epoch:$epoch,lane:$lane,decision:$decision,detail:$detail,request:$request}')" || return 1
}

fail_lane() {
  FLAGS+=("$1")
  EXIT_STATUS="$2"
}

lane_selected() {
  ((${#TARGET_LANES[@]})) || return 0
  local t
  for t in "${TARGET_LANES[@]}"; do [[ "$t" == "$1" ]] && return 0; done
  return 1
}

process_lane() {
  local idx="$1" now="$2"
  local lane repo issue marker instance bodies body state request req reason used n i found=0
  local comment_marker sibling_request sibling_instance author
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
    author="$(lane_telemetry_field "$idx" author)"
    if [[ -n "$author" && ! "$author" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
      record "$lane" "error" "telemetry.author is not a GitHub user login: $(sanitize "$author")" null "$now"
      fail_lane "config-error($lane)" 3
      return 0
    fi
    if ! issue="$(resolve_issue_by_title "$repo" "Lane telemetry: $lane" "$author")"; then
      record "$lane" "api-error" "could not read a complete issue search on $repo; telemetry issue unresolved, not restarting" null "$now"
      fail_lane "api-error($lane)" 5
      return 0
    fi
    [[ -n "$issue" ]] || {
      record "$lane" "no-telemetry" "no open issue titled 'Lane telemetry: $lane' opened by $WRITE_IDENTITY; bind lanes[].telemetry.issue" null "$now"
      return 0
    }
  fi

  marker="$(lane_telemetry_field "$idx" marker)"
  instance="$(lane_telemetry_field "$idx" instance)"
  if ! bodies="$(lane_comment_bodies "$lane" "$repo" "$issue")"; then
    record "$lane" "api-error" "could not read the comments on #$issue (gh api); state unknown, not restarting" null "$now"
    fail_lane "api-error($lane)" 5
    return 0
  fi
  n="$(jq -r 'length' <<<"$bodies" 2>/dev/null)" || n=0
  request="null"
  sibling_request="null"
  sibling_instance=""
  for ((i = 0; i < n; i++)); do
    body="$(jq -r ".[$i]" <<<"$bodies")"
    [[ "$body" == *"$SENTINEL_PREFIX"* ]] || continue
    lane_comment_marker_matches "$body" "$marker" "$instance" || continue
    state="$(extract_state_block "$body")" || continue
    found=1
    req="$(jq -c '.restart_request' <<<"$state")"
    comment_marker="${body#*"$SENTINEL_PREFIX"}"
    comment_marker="${comment_marker%%[[:space:]]*}"
    if [[ "$comment_marker" == *@* && "$marker" != *@* && -z "$instance" ]]; then
      if [[ "$req" != "null" && "$sibling_request" == "null" ]]; then
        sibling_request="$req"
        sibling_instance="${comment_marker#*@}"
      fi
      continue
    fi
    request="$req"
    [[ "$request" != "null" ]] && break
  done

  if ((!found)); then
    record "$lane" "no-state" "no sentinel comment with a parseable state block on #$issue" null "$now"
    return 0
  fi
  if [[ "$request" == "null" ]]; then
    if [[ "$sibling_request" != "null" ]]; then
      record "$lane" "unbound-instance" "restart_request from writer instance '$(sanitize "$sibling_instance")' but this binding pins no instance; bind lanes[].telemetry.instance (or write the @<instance> suffix into marker) to consume it" "$sibling_request" "$now"
      return 0
    fi
    record "$lane" "no-request" "restart_request is null" null "$now"
    return 0
  fi

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

  if ! read_sessions; then
    record "$lane" "error" "could not re-read the session list immediately before relaunching; not restarting on a stale snapshot" "$request" "$now" || true
    fail_lane "session-recheck-failed($lane)" 5
    return 0
  fi
  if lane_is_running "$lane"; then
    record "$lane" "skipped-running" "lane started after the run's snapshot; not restarting ($reason)" "$request" "$now" || true
    return 0
  fi

  if ! ledger_writable; then
    record "$lane" "error" "run ledger is not writable; refusing to relaunch a lane whose attempt cannot be counted" "$request" "$now" || true
    fail_lane "ledger-unwritable($lane)" 5
    return 0
  fi

  info "restarting lane '$lane' ($reason)"
  local -a launch=(restart "$lane" --config "$CONFIG" --repo "$REPO")
  [[ -n "$DATA_DIR_OVERRIDE" ]] && launch+=(--data-dir "$DATA_DIR_OVERRIDE")
  if ! bash "$LAUNCHER" "${launch[@]}"; then
    record "$lane" "failed" "lane-launcher.sh restart exited non-zero" "$request" "$now" ||
      fail_lane "ledger-unwritable($lane)" 5
    fail_lane "restart-failed($lane)" 5
    return 0
  fi

  if confirm_running "$lane"; then
    if ! record "$lane" "restarted" "$reason" "$request" "$now"; then
      err "lane '$lane' WAS relaunched but its breaker row could not be written; later ticks cannot count this attempt"
      fail_lane "ledger-unwritable($lane)" 5
    fi
  else
    record "$lane" "failed" "relaunched but the lane never appeared in the session list" "$request" "$now" ||
      fail_lane "ledger-unwritable($lane)" 5
    fail_lane "restart-unconfirmed($lane)" 5
  fi
}

upsert_own_telemetry() {
  local now="$1" issue body flagstr row upsert
  ((NO_TELEMETRY || DRY_RUN)) && return 0
  [[ "$ACTION" == "run" ]] || return 0

  issue="$TELEMETRY_ISSUE"
  [[ -n "$issue" ]] || issue="$(gh issue list --repo "$TARGET_REPO" --state open \
    --search "loop-lane telemetry running per-lane status in:title" --limit 100 \
    --json number 2>/dev/null | jq -r 'sort_by(.number) | .[0].number // empty')"
  if [[ -z "$issue" && -z "$WRITE_IDENTITY" ]] && ! resolve_write_identity; then
    WRITE_IDENTITY=""
  fi
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
  body+="

Run ledger: \`<data-dir>/$(ledger_relpath)\` on the machine running this consumer."

  upsert="$(dirname "${BASH_SOURCE[0]}")/telemetry-upsert.sh"
  [[ -f "$upsert" ]] || {
    warn "telemetry-upsert.sh not found next to this script; skipping the status comment"
    return 0
  }
  printf '%s\n' "$body" |
    bash "$upsert" --issue "$issue" --marker "$CONSUMER_MARKER" --body-file - --repo "$TARGET_REPO" \
      ${APP_SLUG:+--app-slug "$APP_SLUG"} ||
    warn "the consumer's telemetry upsert failed (the restarts themselves are unaffected)"
}

print_report_header() {
  info "restart-consumer: $ACTION on ${TARGET_REPO:-<fixtures>} at $(iso_utc "$1")"
  info "| lane | decision | detail |"
  info "|---|---|---|"
}

action_print_schedule() {
  local self claude_bin run_cmd win_repo win_claude data_dir opts opts_sq perm_flags cli_ver
  self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
  opts=""
  [[ -n "$CONFIG" ]] && opts+=" --config $CONFIG"
  [[ -n "$TARGET_REPO" ]] && opts+=" --target-repo $TARGET_REPO"
  [[ -n "$APP_SLUG" ]] && opts+=" --app-slug $APP_SLUG"
  opts_sq=""
  [[ -n "$CONFIG" ]] && opts_sq+=" --config '$CONFIG'"
  [[ -n "$TARGET_REPO" ]] && opts_sq+=" --target-repo '$TARGET_REPO'"
  [[ -n "$APP_SLUG" ]] && opts_sq+=" --app-slug '$APP_SLUG'"
  data_dir="${DATA_DIR_OVERRIDE:-<the CLAUDE_PLUGIN_DATA dir skill runs use>}"
  claude_bin="$(command -v claude 2>/dev/null)" || claude_bin="claude"
  win_repo="$(cygpath -w "$REPO" 2>/dev/null)" || win_repo="$REPO"
  win_claude="$(cygpath -w "$claude_bin" 2>/dev/null)" || win_claude="$claude_bin"
  perm_flags="--permission-mode auto"
  cli_ver="$("$claude_bin" --version 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" || cli_ver=""
  if [[ -n "$cli_ver" ]] && awk -v a="$cli_ver" -v b="$PERMISSION_PROMPTS_MIN_VERSION" 'BEGIN {
    split(a, x, "."); split(b, y, ".")
    for (i = 1; i <= 3; i++) { if (x[i] + 0 != y[i] + 0) exit !(x[i] + 0 > y[i] + 0) }
  }'; then
    perm_flags+=" --permission-prompts none"
  fi
  run_cmd="claude -p \"/harness-ops:lanes consume-restarts run${opts}\" ${perm_flags} --output-format text"

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

schtasks /Create /TN "$TASK_NAME" /SC MINUTE /MO ${INTERVAL_MINUTES} /F /RU "%USERNAME%" /IT /RL LIMITED /TR "cmd /c cd /d \"$win_repo\" && \"$win_claude\" -p \"/harness-ops:lanes consume-restarts run${opts}\" ${perm_flags} --output-format text"

  /IT runs the task only while that user is logged on, so the CLI reads the
  credentials already in the user profile: no stored password, no elevation.
  schtasks has no working-directory flag, hence the 'cmd /c cd /d' wrapper.

  Cold start after a reboot — add a logon trigger alongside the poll:

schtasks /Create /TN "$TASK_NAME (logon)" /SC ONLOGON /F /RU "%USERNAME%" /IT /RL LIMITED /TR "cmd /c cd /d \"$win_repo\" && \"$win_claude\" -p \"/harness-ops:lanes consume-restarts run${opts}\" ${perm_flags} --output-format text"

  Remove both (also from cmd.exe):

schtasks /Delete /TN "$TASK_NAME" /F
schtasks /Delete /TN "$TASK_NAME (logon)" /F

== macOS (launchd user agent) / Linux (systemd --user timer, or cron) ==

  Same command on the same interval. cron form:

*/${INTERVAL_MINUTES} * * * * cd '$REPO' && '$claude_bin' -p '/harness-ops:lanes consume-restarts run${opts}' ${perm_flags} --output-format text

== Offline variant (no model turn) ==

  The reader is a deterministic script; the headless 'claude -p' wrapper only
  routes through the skill. Schedule this where a model turn is unwanted:

bash '$self' run --repo '$REPO' --data-dir '$data_dir'${opts_sq}

  --data-dir matters here: skill-invoked runs pass the resolved
  CLAUDE_PLUGIN_DATA directory explicitly, and this form's env-var fallback
  can resolve elsewhere — two directories would split the circuit-breaker
  ledger and widen the effective restart budget.
EOF
}

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
  require_write_identity
  require_claude
  load_sessions

  local now n i lock_rc=0
  now="$(now_epoch)"

  if [[ "$ACTION" == "run" ]] && ((!DRY_RUN)); then
    acquire_lock "$now" || lock_rc=$?
    if ((lock_rc == 2)); then
      err "restart-consumer: the lock store is unusable — not a held lock; failing rather than reporting a skipped tick"
      exit 4
    fi
    if ((lock_rc != 0)); then
      warn "another restart-consumer run holds the lock ($LOCK_DIR) — skipping this tick"
      print_report_header "$now"
      info "| (none) | lock-held | another run holds $LOCK_DIR; skipped |"
      exit 0
    fi
  fi

  n="$(jq -r '(.lanes // []) | length' "$CONFIG")"
  for ((i = 0; i < n; i++)); do process_lane "$i" "$now"; done

  print_report_header "$now"
  if ((${#REPORT_ROWS[@]})); then
    printf '%s\n' "${REPORT_ROWS[@]}"
  else
    info "| (none) | no-lanes | no configured lane matched |"
  fi

  upsert_own_telemetry "$now"
  exit "$EXIT_STATUS"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
