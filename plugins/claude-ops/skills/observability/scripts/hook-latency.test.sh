#!/usr/bin/env bash
# Black-box contract tests for hook-latency.sh against tiny OTLP/JSON fixture stores
# (CC_OTEL_STORE points at a temp dir; the real store is never read). The cases need the real
# duckdb query, so they gate on `command -v duckdb` (CI installs it in ci.yml test-linux).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT="$SCRIPT_DIR/hook-latency.sh"

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

# Shape of a real Collector record; cc_logs_from binds intValue, traceId and spanId, so the
# fixture must carry them.
record() { # <session> <hook_event> <ms> <seconds-ago>
  printf '{"timeUnixNano":"%s000000000","body":{"stringValue":"claude_code.hook_execution_complete"},"attributes":[{"key":"claude.lane","value":{"stringValue":"windows"}},{"key":"session.id","value":{"stringValue":"%s"}},{"key":"event.name","value":{"stringValue":"hook_execution_complete"}},{"key":"event.sequence","value":{"intValue":"7"}},{"key":"hook_event","value":{"stringValue":"%s"}},{"key":"total_duration_ms","value":{"stringValue":"%s"}}],"traceId":"","spanId":""}' \
    "$((EPOCHSECONDS - $4))" "$1" "$2" "$3"
}
line() { # <records...>: one Collector batch line
  local IFS=,
  printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[%s]}]}]}\n' "$*"
}
store() { # <name> <ms-expression in pos> <sessions> <fires> [age-seconds]: Stop fires only
  local d="$TMP/$1" s p recs age="${5:-3600}"
  mkdir -p "$d"
  for ((s = 1; s <= $3; s++)); do
    recs=()
    for ((p = 1; p <= $4; p++)); do recs+=("$(record "sess-$s" Stop "$(($2))" "$((age - p))")"); done
    line "${recs[@]}" >>"$d/cc-logs.json"
  done
  printf '%s' "$d"
}
run() { # <store> <args...>
  out="$(CC_OTEL_STORE="$1" bash "$SCRIPT" "${@:2}" 2>&1)"
  rc=$?
}
flagged() { grep '^!' <<<"$out"; } # rows the script marked

out="$(bash "$SCRIPT" --help)"
assert_contains "--help prints usage" "$out" "--min-sessions"
run "$TMP" --budget nope
assert_eq "bad --budget exits 2" 2 "$rc"
run "$TMP" --min-sessions 2
assert_eq "--min-sessions below 3 exits 2" 2 "$rc"

if command -v duckdb >/dev/null 2>&1; then
  rising="$(store rising '100 + 40 * p' 6 25)"
  run "$rising"
  assert_eq "rising Stop latency exits 1" 1 "$rc"
  assert_contains "rising Stop row is slope-flagged" "$(flagged)" "Stop"
  assert_contains "the flag names the slope reason" "$(flagged)" "slope"
  assert_not_contains "rising Stop p95 is within the default budget" "$out" "p95>budget"
  assert_contains "budgets are labeled as judgment" "$out" "judgment, derived from docs/conventions/hook-budget/README.md"

  run "$rising" --budget Stop=99999
  assert_eq "a loose budget does not hide the slope" 1 "$rc"

  flat="$(store flat '200' 6 25)"
  run "$flat"
  assert_eq "flat Stop latency exits 0" 0 "$rc"
  assert_eq "flat Stop row is not flagged" "" "$(flagged)"

  slow="$(store slow '3000' 1 5)"
  run "$slow"
  assert_eq "Stop p95 over budget exits 1" 1 "$rc"
  assert_contains "p95 reason is named" "$out" "p95>budget"
  mixed="$(store mixed '200' 1 5)"
  rec="$(record sess-1 Stop 250 100)"
  line "${rec/'{"stringValue":"250"}'/'{"intValue":"250"}'}" >>"$mixed/cc-logs.json"
  run "$mixed"
  assert_contains "an intValue total_duration_ms fire is counted" "$out" "Stop                     6"

  run "$slow" --budget Stop=5000
  assert_eq "a budget above p95 clears the flag" 0 "$rc"
  run "$slow" --budget Bogus=5
  assert_contains "an unknown --budget event warns" "$out" "Bogus is not a known hook event"

  # The gates: each fixture rises, but fails exactly one slope condition.
  run "$(store few-sessions '100 + 40 * p' 4 25)"
  assert_eq "rising over 4 sessions is below --min-sessions" 0 "$rc"
  run "$(store few-fires '100 + 40 * p' 6 19)"
  assert_eq "19 fires per session is below --min-fires" 0 "$rc"
  run "$(store shallow '200 + p' 6 25)"
  assert_eq "a slope under the 100 ms floor is not flagged" 0 "$rc"

  old="$(store old '200' 1 5 $((2 * 86400)))"
  run "$old" --days 1
  assert_eq "fires before --days are excluded" 2 "$rc"
  assert_contains "the exclusion says why" "$out" "no hook_execution_complete rows"
  run "$old" --since 2000-01-01
  assert_eq "--since before the fires includes them" 0 "$rc"
  assert_contains "a window older than the hot store warns about the cold tier" "$out" "cold tier"

  empty="$TMP/empty"
  mkdir -p "$empty"
  : >"$empty/cc-logs.json"
  run "$empty"
  assert_eq "empty store exits 2" 2 "$rc"
else
  skip_case "duckdb not found — skipping fixture-store cases"
fi

run "$TMP/missing"
assert_eq "missing store exits 2" 2 "$rc"

printf '\n%d case(s), %d failed\n' "$CASE_NUM" "$FAILED"
((FAILED == 0))
