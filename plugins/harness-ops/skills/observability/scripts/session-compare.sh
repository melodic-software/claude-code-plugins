#!/usr/bin/env bash
# /observability compare: one task run as two sessions, side by side from the OTEL store.
# Tokens by type (cache writes their own type), split by model and effort, and each
# session's claude_code.cost.usage reconciled against its api_request events. Read-only.
#
# Usage:
#   bash session-compare.sh <session-a> <session-b>
#
#   Each id is a session.id as the OTEL store records it (letters, digits, '.', '_', '-').
#
# Reads the hot store only: a session `clean` has compacted to the cold tier is reported as
# absent. Costs are the estimate Claude Code reports; on a subscription they measure work,
# not a bill.
#
# Exit: 0 rendered, 2 cannot evaluate (bad arguments, no duckdb, no store, a session with no
# token or cost metric rows, or a non-delta token or cost metric).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTEL_DIR="$SCRIPT_DIR/../otel"

usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() {
  printf 'session-compare: %s\n' "$1" >&2
  exit 2
}

ids=()
for arg in "$@"; do
  case "$arg" in
  -h | --help)
    usage
    exit 0
    ;;
  *)
    # The ids go into SQL string literals, so this pattern is the injection guard.
    [[ "$arg" =~ ^[A-Za-z0-9._-]+$ ]] || die "not a session id: $arg (letters, digits, '.', '_', '-')"
    ids+=("$arg")
    ;;
  esac
done
((${#ids[@]} == 2)) || die "needs exactly two session ids (see --help)"
[[ "${ids[0]}" != "${ids[1]}" ]] || die "needs two different sessions"

sql_path() { # native duckdb.exe cannot read MSYS paths; double quotes for a SQL literal
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then p="$(cygpath -m "$p")"; fi
  printf '%s\n' "${p//\'/\'\'}"
}

store="${CC_OTEL_STORE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.claude/observability/otel}"
for f in cc-metrics.json cc-logs.json; do
  [[ -f "$store/$f" ]] || die "no store file at $store/$f"
done
command -v duckdb >/dev/null 2>&1 || die "duckdb not found"

err="$(mktemp)"
trap 'rm -f "$err"' EXIT
# Same posture as hook-latency.sh: CC_OTEL_STORE points cc-otel.sql's eager hot views at an
# empty dir so they fail fast (`.bail off` keeps the macros); the queries read the real store
# through the macros. The init's expected bind errors land in $err, shown only on failure.
# `.bail off` also carries the -c statements past an error with exit 0, so success is the
# temporality check's `checked` row and one cost row per session.
rows="$(CC_OTEL_STORE="$SCRIPT_DIR/.no-store" duckdb -list -noheader -separator $'\t' -nullvalue '' \
  -init "$(sql_path "$OTEL_DIR/cc-otel.sql")" \
  -c "SET VARIABLE metrics_src = '$(sql_path "$store/cc-metrics.json")';
SET VARIABLE logs_src = '$(sql_path "$store/cc-logs.json")';
SET VARIABLE a = '${ids[0]}';
SET VARIABLE b = '${ids[1]}';
$(cat "$OTEL_DIR/session-compare.sql")" 2>"$err" | tr -d '\r')"
if [[ "$(grep -c '^cost'$'\t' <<<"$rows")" != 2 ]] || ! grep -q '^checked'$'\t' <<<"$rows"; then
  tail -n 5 "$err" >&2
  die "duckdb query failed"
fi

# The store path rides in the environment: awk -v would read a Windows path's backslashes as escapes.
printf '%s\n' "$rows" | STORE="$store" awk -F'\t' -v a="${ids[0]}" -v b="${ids[1]}" '
function width(s, w) { return length(s) > w ? length(s) : w }
$1 == "temporality" { bad = bad sprintf("  %s, session %s: aggregationTemporality %s\n", $2, $3, $4) }
$1 == "tokens" {
  nt++; tok[nt] = $0
  sw = width($2, sw); mw = width($3, mw); ew = width($4, ew)
  for (i = 5; i <= 8; i++) total[$2, i] += $i
}
$1 == "cost" {
  nc++; cost[nc] = $0
  if ($3 == 0) missing = missing " " $2
  status[$8] = 1
}
END {
  if (bad != "") {
    printf "session-compare: cannot reconcile: cumulative metrics. Summing data points is valid for delta temporality only; the exporter sends\n%sSet OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta (the documented default).\n", bad > "/dev/stderr"
    exit 2
  }
  if (missing != "") {
    printf "session-compare: no token or cost metric rows for session(s)%s in the hot store at %s. The session may have aged to the cold tier, or ran with OTEL_METRICS_INCLUDE_SESSION_ID off.\n", missing, ENVIRON["STORE"] > "/dev/stderr"
    exit 2
  }
  sw = width(a, width(b, width("session", sw))); mw = width("(all)", width("model", mw)); ew = width("(all)", width("effort", ew))
  printf "Same-task comparison: %s vs %s (hot store %s)\n", a, b, ENVIRON["STORE"]
  print "Context: measure with https://code.claude.com/docs/en/monitoring-usage (token and cost counters); correlate: \"What a task costs on Opus 5.5\", https://claude.dev/blog/what-a-task-costs-on-opus-5-5/#measure-it-yourself"
  print "Costs are the estimate Claude Code reports; on a subscription they measure work, not a bill.\n"
  fmt = "%-" sw "s  %-" mw "s  %-" ew "s  %10s  %10s  %12s  %13s\n"
  print "Tokens by type (claude_code.token.usage); effort none = the request carried no effort level"
  printf fmt, "session", "model", "effort", "input", "output", "cacheRead", "cacheCreation"
  for (r = 1; r <= nt; r++) { split(tok[r], f, "\t"); printf fmt, f[2], f[3], f[4], f[5], f[6], f[7], f[8] }
  for (k = 1; k <= 2; k++) {
    s = (k == 1) ? a : b
    printf fmt, s, "(all)", "(all)", total[s, 5] + 0, total[s, 6] + 0, total[s, 7] + 0, total[s, 8] + 0
  }
  cfmt = "%-" sw "s  %10s  %10s  %10s  %12s  %s\n"
  print "\nCost reconciliation (claude_code.cost.usage, the total of record, vs api_request events)"
  printf cfmt, "session", "metric_usd", "events_usd", "gap_usd", "api_requests", "status"
  for (r = 1; r <= nc; r++) {
    split(cost[r], f, "\t")
    printf cfmt, f[2], sprintf("%.6f", f[4]), sprintf("%.6f", f[5]), sprintf("%.6f", (f[8] == "match") ? 0 : f[6]), f[7], f[8]
  }
  if ("events short" in status)
    print "events short: api_request events can be missing for requests whose response contains text, and for side queries (anthropics/claude-code#98193); compare costs on metric_usd."
  if ("events exceed metric" in status)
    print "events exceed metric: unexplained; look for a duplicate export or two Collectors writing one store."
}'
