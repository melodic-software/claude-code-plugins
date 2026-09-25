#!/usr/bin/env bash
# /observability latency — hook p95 against a budget and within-session latency growth, per
# (lane, hook_event), from hook_execution_complete events in the OTEL logs store. Read-only.
#
# Usage:
#   bash hook-latency.sh [--days N | --since YYYY-MM-DD] [--budget EVENT=MS]...
#                        [--min-fires N] [--min-sessions N]
#
#   --days N          window starts now minus N days
#   --since DATE      window starts DATE 00:00 UTC
#                     (default: 2026-09-24, the day the fixed plugins were installed)
#   --budget EVENT=MS p95 budget in ms for EVENT; repeatable, overrides the defaults below
#   --min-fires N     fires one session needs on an event before its slope counts (default 20)
#   --min-sessions N  sessions with a slope an event needs before it can be slope-flagged (default 5)
#
# A full read of a large store takes about a minute: run it on demand or from a routine or
# loop, never from a SessionStart hook.
#
# Exit: 0 nothing flagged, 1 at least one row flagged, 2 cannot evaluate (no duckdb, no store,
# or no hook_execution_complete rows in the window).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTEL_DIR="$SCRIPT_DIR/../otel"

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() {
  printf 'hook-latency: %s\n' "$1" >&2
  exit 2
}

# Judgment, derived from docs/conventions/hook-budget/README.md 'after at S=80 ms' table.
declare -A BUDGET=([Stop]=2000 [PostToolBatch]=1500 [UserPromptSubmit]=1500 [SubagentStop]=1500)
since="2026-09-24 00:00:00"
min_fires=20
min_sessions=5

while (($#)); do
  case "$1" in
  --days)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--days needs a whole number"
    since="$(date -u -d "@$((EPOCHSECONDS - $2 * 86400))" '+%Y-%m-%d %H:%M:%S')"
    shift 2
    ;;
  --since)
    [[ "${2:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || die "--since needs YYYY-MM-DD"
    since="$2 00:00:00"
    shift 2
    ;;
  --budget)
    [[ "${2:-}" =~ ^([A-Za-z]+)=([0-9]+)$ ]] || die "--budget needs EVENT=MS"
    BUDGET[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
    shift 2
    ;;
  --min-fires)
    [[ "${2:-}" =~ ^([2-9]|[1-9][0-9]+)$ ]] || die "--min-fires needs a whole number >= 2"
    min_fires="$2"
    shift 2
    ;;
  --min-sessions)
    [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die "--min-sessions needs a whole number >= 1"
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

# CC_OTEL_STORE points cc-otel.sql's eager hot views at an empty dir so they fail fast
# (`.bail off` keeps the macros); the query reads the real store through cc_logs_from.
rows="$(CC_OTEL_STORE="$SCRIPT_DIR/.no-store" duckdb -csv -noheader \
  -init "$(sql_path "$OTEL_DIR/cc-otel.sql")" \
  -c "SET VARIABLE src = '$(sql_path "$store/cc-logs.json")';
SET VARIABLE since = TIMESTAMP '$since';
SET VARIABLE min_fires = $min_fires;
$(cat "$OTEL_DIR/hook-latency.sql")" 2>/dev/null | tr -d '\r')" || die "duckdb query failed"
[[ -n "$rows" ]] || die "no hook_execution_complete rows since $since UTC"

budgets=""
for event in "${!BUDGET[@]}"; do budgets+="$event=${BUDGET[$event]},"; done

printf 'Hook latency since %s UTC (store %s)\n' "$since" "$store"
printf 'p95 budgets: judgment, derived from docs/conventions/hook-budget/README.md '\''after at S=80 ms'\'' table; other events report-only.\n'
printf 'slope flag (judgment): >= %s sessions with >= %s fires, sign-test z >= 1.645, median slope >= max(100 ms, 0.5 x p50).\n\n' \
  "$min_sessions" "$min_fires"

printf '%s\n' "$rows" | awk -F, -v budgets="$budgets" -v min_sessions="$min_sessions" '
BEGIN {
  n = split(budgets, pairs, ",")
  for (i = 1; i <= n; i++) if (split(pairs[i], kv, "=") == 2) budget[kv[1]] = kv[2]
  fmt = "%-1s %-8s %-18s %7s %6s %7s %7s %7s %6s %7s %5s  %s\n"
  printf fmt, "", "lane", "hook_event", "fires", "sess", "p50", "p95", "budget", "slope_n", "slope", "pos", "reason"
  flagged = 0
}
{
  if ($8 == "NULL") $8 = ""
  b = ($2 in budget) ? budget[$2] : "n/a"
  reason = ""
  if (b != "n/a" && $6 + 0 > b + 0) reason = "p95>budget"
  sn = $7 + 0; pos = $9 + 0
  if (sn >= min_sessions && $8 != "") {
    z = (pos - sn / 2) / sqrt(sn / 4)
    floor_ms = 0.5 * $5; if (floor_ms < 100) floor_ms = 100
    if (z >= 1.645 && $8 + 0 >= floor_ms) reason = reason (reason ? "," : "") "slope"
  }
  if (reason != "") flagged++
  printf fmt, (reason ? "!" : ""), $1, $2, $3, $4, $5, $6, b, $7, ($8 == "" ? "-" : $8), $9, reason
}
END { exit(flagged ? 1 : 0) }'
