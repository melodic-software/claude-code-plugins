#!/usr/bin/env bash
# Black-box contract tests for item-rollup.sh against tiny OTLP/JSON fixture stores
# (CC_OTEL_STORE points at a temp dir; the real store is never read). The cases that need the
# real duckdb query gate on `command -v duckdb`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT="$SCRIPT_DIR/item-rollup.sh"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s: expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
skip_case() { printf 'SKIP: %s\n' "$1" >&2; }
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

readonly ITEM_A=https://github.com/o/r/issues/1
readonly ITEM_B=https://github.com/o/r/issues/2

# Shared attributes: <session> <item|-> <ccr|->. A `-` leaves the attribute out.
attrs() {
  local out="{\"key\":\"session.id\",\"value\":{\"stringValue\":\"$1\"}}"
  [[ "$2" == - ]] || out+=",{\"key\":\"autonomy.work_item.url\",\"value\":{\"stringValue\":\"$2\"}}"
  [[ "$3" == - ]] || out+=",{\"key\":\"ccr.session.id\",\"value\":{\"stringValue\":\"$3\"}}"
  printf '%s' "$out"
}
# Metric data point: <session> <item|-> <ccr|-> <type|-> <value fragment, e.g. "asInt":"5">.
point() {
  local a
  a="$(attrs "$1" "$2" "$3")"
  [[ "$4" == - ]] || a+=",{\"key\":\"type\",\"value\":{\"stringValue\":\"$4\"}}"
  printf '{"timeUnixNano":"%s000000000","attributes":[%s],%s}' "$EPOCHSECONDS" "$a" "$5"
}
metric() { # <name> <aggregationTemporality> <points...>: one Collector batch line
  local name="$1" temporality="$2" IFS=,
  shift 2
  printf '{"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"name":"%s","unit":"x","sum":{"dataPoints":[%s],"aggregationTemporality":%s,"isMonotonic":true}}]}]}]}\n' \
    "$name" "$*" "$temporality"
}
# Log event: <session> <item|-> <ccr|-> <event name> [extra attribute fragment]. cc_logs_from
# binds intValue on event.sequence, so the record carries it, as a real one does.
event() {
  printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s000000000","body":{"stringValue":"claude_code.%s"},"attributes":[%s,{"key":"event.name","value":{"stringValue":"%s"}},{"key":"event.sequence","value":{"intValue":"1"}}%s],"traceId":"","spanId":""}]}]}]}\n' \
    "$EPOCHSECONDS" "$4" "$(attrs "$1" "$2" "$3")" "$4" "${5:+,$5}"
}
TOKENS=claude_code.token.usage
COST=claude_code.cost.usage

run() { # <store> <args...>
  out="$(CC_OTEL_STORE="$1" bash "$SCRIPT" "${@:2}" 2>&1)"
  rc=$?
  flat="$(tr -s ' ' <<<"$out")"
}

# Usage errors need no store and no duckdb.
out="$(bash "$SCRIPT" --help)"
assert_contains "--help prints usage" "$out" "--session-map"
run "$TMP" --bogus
assert_eq "an unknown argument exits 2" 2 "$rc"
run "$TMP" --session-map "$TMP/absent.tsv"
assert_eq "a missing session map exits 2" 2 "$rc"
printf "cse_1\t%s'); DROP TABLE x; --\n" "$ITEM_B" >"$TMP/quote.tsv"
run "$TMP" --session-map "$TMP/quote.tsv"
assert_eq "a map line with a quote exits 2" 2 "$rc"
assert_contains "the bad map line is named" "$out" "session map line 1"
printf 'cse_1\t%s/\n' "$ITEM_B" >"$TMP/slash.tsv"
run "$TMP" --session-map "$TMP/slash.tsv"
assert_eq "a map URL with a trailing slash exits 2" 2 "$rc"
assert_contains "the trailing-slash line is named" "$out" "session map line 1"
run "$TMP/missing"
assert_eq "a missing store exits 2" 2 "$rc"
assert_contains "the missing store names the metrics file" "$out" "cc-metrics.json"

if command -v duckdb >/dev/null 2>&1; then
  # Two items, each with one local session; one cloud session (s-3, ccr.session.id cse_1)
  # whose metrics carry no item.
  main="$TMP/main"
  mkdir -p "$main"
  {
    metric "$TOKENS" 1 \
      "$(point s-1 "$ITEM_A" - input '"asInt":"100"')" \
      "$(point s-1 "$ITEM_A" - output '"asDouble":20')" \
      "$(point s-1 "$ITEM_A" - cacheRead '"asInt":"1000"')" \
      "$(point s-1 "$ITEM_A" - cacheCreation '"asInt":"50"')"
    metric "$TOKENS" 1 \
      "$(point s-2 "$ITEM_B" - input '"asInt":"10"')" \
      "$(point s-2 "$ITEM_B" - output '"asInt":"5"')"
    metric "$TOKENS" 1 \
      "$(point s-3 - cse_1 input '"asInt":"7"')" \
      "$(point s-3 - cse_1 output '"asInt":"3"')" \
      "$(point s-3 - cse_1 cacheCreation '"asInt":"30"')"
    metric "$COST" 1 "$(point s-1 "$ITEM_A" - - '"asDouble":1.2345')"
  } >"$main/cc-metrics.json"
  {
    event s-1 "$ITEM_A" - user_prompt
    event s-1 "$ITEM_A" - user_prompt
    event s-1 "$ITEM_A" - api_request '{"key":"cost_usd","value":{"doubleValue":6.789}}'
    event s-2 "$ITEM_B" - user_prompt
    event s-3 - cse_1 user_prompt
    event s-3 - cse_1 user_prompt
  } >"$main/cc-logs.json"
  before="$(cat "$main"/* | cksum)"

  run "$main"
  assert_eq "a rollup exits 0" 0 "$rc"
  assert_contains "columns" "$flat" "item sessions cloud turns input output cacheRead cacheCreation tokens"
  assert_contains "item A totals" "$flat" "$ITEM_A 1 0 2 100 20 1000 50 1170"
  assert_contains "item B totals, local only" "$flat" "$ITEM_B 1 0 1 10 5 0 0 15"
  assert_contains "an unmapped cloud session is unattributed" "$flat" "(no item) 1 1 2 7 3 0 30 40"
  assert_not_contains "no cost metric value" "$out" "1.2345"
  assert_not_contains "no api_request cost" "$out" "6.789"
  # The store path is random text, so it is cut before looking for a currency mark.
  assert_not_contains "no dollar sign" "${out//$main/}" '$'
  assert_not_contains "no usd" "${out//$main/}" "usd"

  printf '# dispatcher record\n\ncse_1\t%s\n' "$ITEM_B" >"$TMP/map.tsv"
  run "$main" --session-map "$TMP/map.tsv"
  assert_eq "a mapped rollup exits 0" 0 "$rc"
  assert_contains "the map joins the cloud session to item B" "$flat" "$ITEM_B 2 1 3 17 8 0 30 55"
  assert_contains "item A is unchanged" "$flat" "$ITEM_A 1 0 2 100 20 1000 50 1170"
  assert_not_contains "nothing is left unattributed" "$out" "(no item)"
  assert_contains "the cloud session row" "$flat" "$ITEM_B cse_1 2 7 3 0 30"
  assert_eq "the store is not modified" "$before" "$(cat "$main"/* | cksum)"

  # The cloud session's events carry item B, its metrics do not: the store's own pairs map it.
  instore="$TMP/instore"
  mkdir -p "$instore"
  cp "$main/cc-metrics.json" "$instore/"
  {
    event s-1 "$ITEM_A" - user_prompt
    event s-1 "$ITEM_A" - user_prompt
    event s-2 "$ITEM_B" - user_prompt
    event s-3 "$ITEM_B" cse_1 user_prompt
    event s-3 "$ITEM_B" cse_1 user_prompt
  } >"$instore/cc-logs.json"
  run "$instore"
  assert_eq "an in-store mapped rollup exits 0" 0 "$rc"
  assert_contains "pairs in the store join the cloud session to item B" "$flat" "$ITEM_B 2 1 3 17 8 0 30 55"

  printf 'cse_1\t%s\n' "$ITEM_A" >"$TMP/conflict.tsv"
  run "$instore" --session-map "$TMP/conflict.tsv"
  assert_eq "a conflicting map still renders" 0 "$rc"
  assert_contains "a cloud session tied to two items is named" "$out" "tied to more than one item: cse_1"
  assert_contains "its item-less tokens stay unattributed" "$flat" "(no item) 1 1 0 7 3 0 30 40"
  assert_contains "its own-item turns stay with item B" "$flat" "$ITEM_B 2 1 3 10 5 0 0 15"

  cumulative="$TMP/cumulative"
  mkdir -p "$cumulative"
  cp "$main/cc-logs.json" "$cumulative/"
  metric "$TOKENS" 2 "$(point s-1 "$ITEM_A" - input '"asInt":"100"')" >"$cumulative/cc-metrics.json"
  run "$cumulative"
  assert_eq "a non-delta token metric exits 2" 2 "$rc"
  assert_contains "the non-delta store says why" "$out" "cannot sum cumulative metrics"

  empty="$TMP/empty"
  mkdir -p "$empty"
  : >"$empty/cc-metrics.json"
  : >"$empty/cc-logs.json"
  run "$empty"
  assert_eq "an empty store exits 2" 2 "$rc"
else
  skip_case "duckdb not found: skipping fixture-store cases"
fi

printf '\n%d case(s), %d failed\n' "$CASE_NUM" "$FAILED"
((FAILED == 0))
