#!/usr/bin/env bash
# /observability items: tokens and turns per work item from the hot OTEL store. Read-only.
#
# Usage:
#   bash item-rollup.sh [--session-map FILE]
#
#   The item is each row's autonomy.work_item.url attribute. A row without one (a cloud session
#   whose telemetry does not carry it) joins its item through ccr.session.id: the pairs on rows
#   carrying both, plus FILE, one `<ccr.session.id><TAB><item URL>` per line ('#' lines and
#   blank lines skipped; the URL https, with no query, fragment or trailing slash). A cloud
#   session tied to more than one item is left unattributed and named.
#
# Turns are user_prompt events. Tokens are claude_code.token.usage by type. No price: the rollup
# reads no cost metric or cost attribute.
#
# Exit: 0 rendered, 2 cannot evaluate (bad arguments or map file, no duckdb, no store, no token
# or user_prompt rows, or a non-delta token metric).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OTEL_DIR="$SCRIPT_DIR/../otel"

usage() { sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() {
  printf 'item-rollup: %s\n' "$1" >&2
  exit 2
}

map=""
while (($#)); do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --session-map)
    (($# >= 2)) || die "--session-map needs a file"
    map="$2"
    shift 2
    ;;
  *) die "unknown argument: $1 (see --help)" ;;
  esac
done

# The map's values go into SQL string literals, so these patterns are the injection guard.
readonly CCR_RE='^[A-Za-z0-9._-]+$'
readonly URL_RE='^https://[A-Za-z0-9._~:/@!$&()*+,;=%-]+$'
map_sql="CREATE TEMP TABLE file_map (ccr_session_id VARCHAR, item_url VARCHAR);"
if [[ -n "$map" ]]; then
  [[ -f "$map" && -r "$map" ]] || die "no readable session map at $map"
  values=()
  n=0
  while IFS=$'\t' read -r ccr url extra || [[ -n "$ccr" ]]; do
    n=$((n + 1))
    ccr="${ccr%$'\r'}"
    url="${url%$'\r'}"
    [[ -z "$ccr" && -z "$url" || "$ccr" == \#* ]] && continue
    [[ -z "${extra:-}" && "$ccr" =~ $CCR_RE && "$url" =~ $URL_RE && "$url" != */ ]] ||
      die "session map line $n is not <ccr.session.id><TAB><https item URL, no query, fragment or trailing slash>"
    values+=("('$ccr', '$url')")
  done <"$map"
  if ((${#values[@]})); then
    map_sql+=" INSERT INTO file_map VALUES $(
      IFS=,
      printf '%s' "${values[*]}"
    );"
  fi
fi

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
# Same posture as session-compare.sh: CC_OTEL_STORE points cc-otel.sql's eager hot views at an
# empty dir so they fail fast (`.bail off` keeps the macros); the queries read the real store
# through the macros. `.bail off` also carries the -c statements past an error with exit 0, so
# success is the temporality check's `checked` row and the rollup's `done` row.
rows="$(CC_OTEL_STORE="$SCRIPT_DIR/.no-store" duckdb -list -noheader -separator $'\t' -nullvalue '' \
  -init "$(sql_path "$OTEL_DIR/cc-otel.sql")" \
  -c "SET VARIABLE metrics_src = '$(sql_path "$store/cc-metrics.json")';
SET VARIABLE logs_src = '$(sql_path "$store/cc-logs.json")';
$map_sql
$(cat "$OTEL_DIR/item-rollup.sql")" 2>"$err" | tr -d '\r')"
if ! grep -q '^checked'$'\t' <<<"$rows" || ! grep -q '^done'$'\t' <<<"$rows"; then
  tail -n 5 "$err" >&2
  die "duckdb query failed"
fi

# The store path rides in the environment: awk -v would read a Windows path's backslashes as escapes.
printf '%s\n' "$rows" | STORE="$store" awk -F'\t' '
function width(s, w) { return length(s) > w ? length(s) : w }
function label(s) { return s == "" ? "(no item)" : s }
$1 == "temporality" { bad = bad sprintf("  %s: aggregationTemporality %s\n", $2, $3) }
$1 == "item" {
  n++; row[n] = $0
  it = label($2)
  if (!(it in seen)) { seen[it] = 1; ni++; order[ni] = it }
  iw = width(it, iw)
  sessions[it] += $4; turns[it] += $5
  for (i = 6; i <= 9; i++) tok[it, i] += $i
  if ($3 != "") { cloud[it]++; nc++; cw = width($3, cw) }
}
$1 == "ambiguous" { amb = amb " " $2 }
END {
  if (bad != "") {
    printf "item-rollup: cannot sum cumulative metrics. Summing data points is valid for delta temporality only; the exporter sends\n%sSet OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=delta (the documented default).\n", bad > "/dev/stderr"
    exit 2
  }
  if (n == 0) {
    printf "item-rollup: no claude_code.token.usage or user_prompt rows in the hot store at %s.\n", ENVIRON["STORE"] > "/dev/stderr"
    exit 2
  }
  iw = width("item", iw)
  printf "Usage per work item (hot store %s)\n", ENVIRON["STORE"]
  print "Item: autonomy.work_item.url, or the ccr.session.id map for a cloud session without it. Turns: user_prompt events. Tokens: claude_code.token.usage. No price.\n"
  fmt = "%-" iw "s  %8s  %5s  %6s  %10s  %10s  %12s  %13s  %12s\n"
  printf fmt, "item", "sessions", "cloud", "turns", "input", "output", "cacheRead", "cacheCreation", "tokens"
  for (k = 1; k <= ni; k++) {
    it = order[k]
    printf fmt, it, sessions[it], cloud[it] + 0, turns[it], tok[it, 6], tok[it, 7], tok[it, 8], tok[it, 9], tok[it, 6] + tok[it, 7] + tok[it, 8] + tok[it, 9]
  }
  if (nc > 0) {
    cw = width("ccr.session.id", cw)
    cfmt = "%-" iw "s  %-" cw "s  %6s  %10s  %10s  %12s  %13s\n"
    print "\nCloud sessions (grouped by item and ccr.session.id)"
    printf cfmt, "item", "ccr.session.id", "turns", "input", "output", "cacheRead", "cacheCreation"
    for (r = 1; r <= n; r++) {
      split(row[r], f, "\t")
      if (f[3] != "") printf cfmt, label(f[2]), f[3], f[5], f[6], f[7], f[8], f[9]
    }
  }
  if (amb != "")
    printf "\nLeft unattributed, tied to more than one item:%s\n", amb
}'
