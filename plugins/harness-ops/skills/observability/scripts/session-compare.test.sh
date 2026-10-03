#!/usr/bin/env bash
# Black-box contract tests for session-compare.sh against tiny OTLP/JSON fixture stores
# (CC_OTEL_STORE points at a temp dir; the real store is never read). The cases that need the
# real duckdb query gate on `command -v duckdb` (CI installs it in ci.yml test-linux).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT="$SCRIPT_DIR/session-compare.sh"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s — expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
skip_case() { printf 'SKIP: %s\n' "$1" >&2; }
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }
assert_not_contains() { if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1" "absent: $3" "$2"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Metric data point: <session> <model> <effort|-> <type|-> <value fragment, e.g. "asInt":"5">.
# A `-` effort leaves the attribute out, as Claude Code does for a model without effort.
point() {
  local attrs
  attrs="{\"key\":\"session.id\",\"value\":{\"stringValue\":\"$1\"}},{\"key\":\"model\",\"value\":{\"stringValue\":\"$2\"}}"
  [[ "$3" == - ]] || attrs+=",{\"key\":\"effort\",\"value\":{\"stringValue\":\"$3\"}}"
  [[ "$4" == - ]] || attrs+=",{\"key\":\"type\",\"value\":{\"stringValue\":\"$4\"}}"
  printf '{"timeUnixNano":"%s000000000","attributes":[%s],%s}' "$EPOCHSECONDS" "$attrs" "$5"
}
metric() { # <name> <aggregationTemporality> <points...>: one Collector batch line
  local name="$1" temporality="$2" IFS=,
  shift 2
  printf '{"resourceMetrics":[{"scopeMetrics":[{"metrics":[{"name":"%s","unit":"x","sum":{"dataPoints":[%s],"aggregationTemporality":%s,"isMonotonic":true}}]}]}]}\n' \
    "$name" "$*" "$temporality"
}
# api_request log line: <session> <cost attribute fragment>. cc_logs_from binds intValue on
# event.sequence, so the record carries it, as a real one does.
api_request() {
  printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"timeUnixNano":"%s000000000","body":{"stringValue":"claude_code.api_request"},"attributes":[{"key":"session.id","value":{"stringValue":"%s"}},{"key":"event.name","value":{"stringValue":"api_request"}},{"key":"event.sequence","value":{"intValue":"3"}},{"key":"input_tokens","value":{"intValue":"10"}},%s],"traceId":"","spanId":""}]}]}]}\n' \
    "$EPOCHSECONDS" "$1" "$2"
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
assert_contains "--help prints usage" "$out" "session-a"
run "$TMP"
assert_eq "no ids exits 2" 2 "$rc"
run "$TMP" s-a
assert_eq "one id exits 2" 2 "$rc"
run "$TMP" s-a s-a
assert_eq "identical ids exit 2" 2 "$rc"
assert_contains "identical ids are named as the reason" "$out" "two different sessions"
run "$TMP" "s-a' OR 1=1 --" s-b
assert_eq "an id containing a quote exits 2" 2 "$rc"
assert_contains "the quoted id is rejected by the id pattern" "$out" "not a session id"
run "$TMP" s-a s-b s-c
assert_eq "three ids exit 2" 2 "$rc"

run "$TMP/missing" s-a s-b
assert_eq "missing store exits 2" 2 "$rc"
assert_contains "missing store names the metrics file" "$out" "cc-metrics.json"

if command -v duckdb >/dev/null 2>&1; then
  main="$TMP/main"
  mkdir -p "$main"
  {
    # s-a: model m-x, effort high and medium; every value type in both encodings.
    metric "$TOKENS" 1 \
      "$(point s-a m-x high input '"asInt":"100"')" \
      "$(point s-a m-x high input '"asInt":"10"')" \
      "$(point s-a m-x high output '"asDouble":50')" \
      "$(point s-a m-x high cacheRead '"asInt":"1000"')" \
      "$(point s-a m-x high cacheCreation '"asDouble":200')" \
      "$(point s-a m-x medium input '"asInt":"5"')"
    # s-b: model m-y, no effort attribute.
    metric "$TOKENS" 1 \
      "$(point s-b m-y - input '"asInt":"7"')" \
      "$(point s-b m-y - output '"asInt":"3"')" \
      "$(point s-b m-y - cacheCreation '"asInt":"30"')"
    metric "$TOKENS" 1 "$(point s-c m-x low input '"asInt":"1"')" "$(point s-z m-z high input '"asInt":"9999"')"
    # s-t: token points but no cost point.
    metric "$TOKENS" 1 "$(point s-t m-x high input '"asInt":"4"')"
    metric "$COST" 1 \
      "$(point s-a m-x high - '"asDouble":0.75')" \
      "$(point s-a m-x medium - '"asDouble":0.25')" \
      "$(point s-b m-y - - '"asDouble":0.5')" \
      "$(point s-c m-x low - '"asDouble":0.1')" \
      "$(point s-z m-z high - '"asDouble":9')"
  } >"$main/cc-metrics.json"
  {
    api_request s-a '{"key":"cost_usd","value":{"doubleValue":0.4}}'
    api_request s-a '{"key":"cost_usd_micros","value":{"intValue":"200000"}}'
    api_request s-b '{"key":"cost_usd","value":{"stringValue":"0.5"}}'
    api_request s-c '{"key":"cost_usd","value":{"doubleValue":0.3}}'
    api_request s-z '{"key":"cost_usd","value":{"doubleValue":9}}'
    api_request s-t '{"key":"cost_usd","value":{"doubleValue":0.2}}'
  } >"$main/cc-logs.json"
  before="$(cat "$main"/* | cksum)"

  run "$main" s-a s-b
  assert_eq "a rendered comparison exits 0" 0 "$rc"
  assert_contains "cacheCreation is its own column" "$flat" "session model effort input output cacheRead cacheCreation"
  assert_contains "s-a high row sums each type, cache writes not folded into input" "$flat" "s-a m-x high 110 50 1000 200"
  assert_contains "s-a medium effort is its own row" "$flat" "s-a m-x medium 5 0 0 0"
  assert_contains "absent effort renders as unset" "$flat" "s-b m-y unset 7 3 0 30"
  assert_contains "s-a per-type totals" "$flat" "s-a (all) (all) 115 50 1000 200"
  assert_contains "s-b per-type totals" "$flat" "s-b (all) (all) 7 3 0 30"
  assert_not_contains "a session not asked for is left out" "$flat" "9999"
  assert_contains "cost columns" "$flat" "session metric_usd events_usd gap_usd api_requests status"
  assert_contains "events short of the metric (doubleValue and intValue micros counted)" "$flat" "s-a 1.000000 0.600000 0.400000 2 events short"
  assert_contains "events short names the upstream bug" "$out" "anthropics/claude-code#98193"
  assert_contains "metric equal to events matches (stringValue cost counted)" "$flat" "s-b 0.500000 0.500000 0.000000 1 match"
  assert_contains "the context line links the monitoring docs, then the post section" "$out" \
    "Context: measure with https://code.claude.com/docs/en/monitoring-usage (token and cost counters); correlate: \"What a task costs on Opus 5.5\", https://claude.dev/blog/what-a-task-costs-on-opus-5-5/#measure-it-yourself"
  assert_not_contains "the context line states no task count" "$out" "three or four"
  assert_eq "the store is not modified" "$before" "$(cat "$main"/* | cksum)"

  run "$main" s-b s-c
  assert_eq "an events-exceed comparison still renders" 0 "$rc"
  assert_contains "events above the metric are flagged" "$flat" "s-c 0.100000 0.300000 -0.200000 1 events exceed metric"
  assert_not_contains "no shortfall, no upstream-bug note" "$out" "98193"

  run "$main" s-a s-missing
  assert_eq "a session absent from the store exits 2" 2 "$rc"
  assert_contains "the absent session is named" "$out" "s-missing"
  assert_contains "the absence points at the cold tier" "$out" "cold tier"

  run "$main" s-a s-t
  assert_eq "a session with token points but no cost point exits 2" 2 "$rc"
  assert_not_contains "no cost point is not reported as events exceeding the metric" "$out" "events exceed metric"

  cumulative="$TMP/cumulative"
  mkdir -p "$cumulative"
  cp "$main/cc-logs.json" "$cumulative/"
  {
    metric "$TOKENS" 2 "$(point s-a m-x high input '"asInt":"100"')"
    metric "$COST" 1 "$(point s-a m-x high - '"asDouble":1')" "$(point s-b m-y - - '"asDouble":0.5')"
    metric "$TOKENS" 1 "$(point s-b m-y - input '"asInt":"7"')"
  } >"$cumulative/cc-metrics.json"
  run "$cumulative" s-a s-b
  assert_eq "a non-delta metric exits 2" 2 "$rc"
  assert_contains "the non-delta store says why" "$out" "cannot reconcile: cumulative metrics"

  nologs="$TMP/nologs"
  mkdir -p "$nologs"
  cp "$main/cc-metrics.json" "$nologs/"
  run "$nologs" s-a s-b
  assert_eq "a store with no logs file exits 2" 2 "$rc"
  assert_contains "the missing logs file is named" "$out" "cc-logs.json"

  empty="$TMP/empty"
  mkdir -p "$empty"
  : >"$empty/cc-metrics.json"
  : >"$empty/cc-logs.json"
  run "$empty" s-a s-b
  assert_eq "an empty store exits 2" 2 "$rc"
else
  skip_case "duckdb not found — skipping fixture-store cases"
fi

printf '\n%d case(s), %d failed\n' "$CASE_NUM" "$FAILED"
((FAILED == 0))
