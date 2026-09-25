#!/usr/bin/env bash
# /observability latency — hook p95 against a budget and within-session latency growth, per
# (lane, hook_event), from hook_execution_complete events in the OTEL logs store. Read-only.
#
# Usage:
#   bash hook-latency.sh [--days N | --since YYYY-MM-DD] [--budget EVENT=MS]...
#                        [--min-fires N] [--min-sessions N]
#
#   --days N          window starts now minus N days (default 7)
#   --since DATE      window starts DATE 00:00 UTC
#   --budget EVENT=MS p95 budget in ms for EVENT; repeatable, overrides the defaults below
#   --min-fires N     fires one session needs on an event before its slope counts (default 20)
#   --min-sessions N  sessions with a slope an event needs before it can be slope-flagged
#                     (default 5, minimum 3: the sign test cannot flag fewer)
#
# Reads the hot store only: fires older than `clean` keeps hot sit in the cold tier and are
# not included. A full read of a large store takes about a minute: run it on demand or from
# a routine or loop, never from a SessionStart hook.
#
# Exit: 0 nothing flagged, 1 at least one row flagged, 2 cannot evaluate (no duckdb, no store,
# or no hook_execution_complete rows in the window).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTEL_DIR="$SCRIPT_DIR/../otel"

usage() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() {
  printf 'hook-latency: %s\n' "$1" >&2
  exit 2
}

# Judgment, derived from docs/conventions/hook-budget/README.md 'after at S=80 ms' table.
budgets="Stop=2000,PostToolBatch=1500,UserPromptSubmit=1500,SubagentStop=1500,"
readonly KNOWN_EVENTS=" SessionStart Setup UserPromptSubmit UserPromptExpansion PreToolUse PermissionRequest PermissionDenied PostToolUse PostToolUseFailure PostToolBatch Notification MessageDisplay SubagentStart SubagentStop TaskCreated TaskCompleted Stop StopFailure TeammateIdle InstructionsLoaded ConfigChange CwdChanged DirectoryAdded FileChanged WorktreeCreate WorktreeRemove PreCompact PostCompact PreModelSwitch PostModelSwitch Elicitation ElicitationResult SessionEnd "
# Both forms are SQL over digits-only input; make_timestamp(epoch_us(now())) is UTC, the same
# clock cc_logs_from builds event_time on.
since_sql="make_timestamp(epoch_us(now())) - INTERVAL (7) DAY"
min_fires=20
min_sessions=5

while (($#)); do
  case "$1" in
  --days)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--days needs a whole number"
    since_sql="make_timestamp(epoch_us(now())) - INTERVAL ($2) DAY"
    shift 2
    ;;
  --since)
    [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--since needs YYYY-MM-DD"
    since_sql="TIMESTAMP '$2 00:00:00'"
    shift 2
    ;;
  --budget)
    [[ "${2:-}" =~ ^([A-Za-z]+)=([0-9]+)$ ]] || die "--budget needs EVENT=MS"
    [[ "$KNOWN_EVENTS" == *" ${BASH_REMATCH[1]} "* ]] ||
      printf 'hook-latency: warning: %s is not a known hook event; its budget applies only if it appears\n' "${BASH_REMATCH[1]}" >&2
    budgets+="$2,"
    shift 2
    ;;
  --min-fires)
    [[ "${2:-}" =~ ^([2-9]|[1-9][0-9]+)$ ]] || die "--min-fires needs a whole number >= 2"
    min_fires="$2"
    shift 2
    ;;
  --min-sessions)
    [[ "${2:-}" =~ ^([3-9]|[1-9][0-9]+)$ ]] || die "--min-sessions needs a whole number >= 3"
    min_sessions="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown argument: $1 (see --help)" ;;
  esac
done

sql_path() { # native duckdb.exe cannot read MSYS paths; double quotes for a SQL literal
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then p="$(cygpath -m "$p")"; fi
  printf '%s\n' "${p//\'/\'\'}"
}

command -v duckdb >/dev/null 2>&1 || die "duckdb not found"
store="${CC_OTEL_STORE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/observability/otel}"
[[ -f "$store/cc-logs.json" ]] || die "no logs store at $store/cc-logs.json"

err="$(mktemp)"
trap 'rm -f "$err"' EXIT
# CC_OTEL_STORE points cc-otel.sql's eager hot views at an empty dir so they fail fast
# (`.bail off` keeps the macros); the query reads the real store through cc_logs_from.
# The init's expected hot-view bind errors also land in $err, so only a failed exit shows it.
if ! rows="$(CC_OTEL_STORE="$SCRIPT_DIR/.no-store" duckdb -list -noheader -separator $'\t' -nullvalue '' \
  -init "$(sql_path "$OTEL_DIR/cc-otel.sql")" \
  -c "SET VARIABLE src = '$(sql_path "$store/cc-logs.json")';
SET VARIABLE since = $since_sql;
SET VARIABLE min_fires = $min_fires;
$(cat "$OTEL_DIR/hook-latency.sql")" 2>"$err" | tr -d '\r')"; then
  tail -n 5 "$err" >&2
  die "duckdb query failed"
fi

# The store path rides in the environment: awk -v would read a Windows path's backslashes as escapes.
printf '%s\n' "$rows" | STORE="$store" awk -F'\t' -v budgets="$budgets" -v min_sessions="$min_sessions" -v min_fires="$min_fires" '
BEGIN {
  n = split(budgets, pairs, ",")
  for (i = 1; i <= n; i++) if (split(pairs[i], kv, "=") == 2) budget[kv[1]] = kv[2]
  fmt = "%-1s %-8s %-18s %7s %6s %7s %7s %7s %6s %7s %5s  %s\n"
  flagged = 0
}
NR == 1 {
  if ($3 == "") {
    printf "hook-latency: no hook_execution_complete rows since %s UTC\n", $1 > "/dev/stderr"
    empty = 1
    exit
  }
  printf "Hook latency since %s UTC (store %s)\n", $1, ENVIRON["STORE"]
  if ($2 > $1)
    printf "warning: the oldest hot fire is %s UTC; older fires sit in the cold tier (clean compacts after --keep-days) and are not included.\n", $2
  print "p95 budgets: judgment, derived from docs/conventions/hook-budget/README.md '\''after at S=80 ms'\'' table; other events report-only."
  printf "slope flag (judgment): >= %s sessions with >= %s fires, sign-test z >= 1.645, median slope >= max(100 ms, 0.5 x p50).\n\n", min_sessions, min_fires
  printf fmt, "", "lane", "hook_event", "fires", "sess", "p50", "p95", "budget", "slope_n", "slope", "pos", "reason"
}
{
  b = ($4 in budget) ? budget[$4] : "n/a"
  reason = ""
  if (b != "n/a" && $8 + 0 > b + 0) reason = "p95>budget"
  sn = $9 + 0; pos = $11 + 0
  if (sn >= min_sessions && $10 != "") {
    z = (pos - sn / 2) / sqrt(sn / 4)
    floor_ms = 0.5 * $7; if (floor_ms < 100) floor_ms = 100
    if (z >= 1.645 && $10 + 0 >= floor_ms) reason = reason (reason ? "," : "") "slope"
  }
  if (reason != "") flagged++
  printf fmt, (reason ? "!" : ""), $3, $4, $5, $6, $7, $8, b, $9, ($10 == "" ? "-" : $10), $11, reason
}
END { exit(empty ? 2 : flagged ? 1 : 0) }'
