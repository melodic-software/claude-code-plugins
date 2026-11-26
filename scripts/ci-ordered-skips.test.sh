#!/usr/bin/env bash
# test-scope: .github/workflows/pr-require-checks.yml .github/workflows/pr-unblock.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/pr-require-checks.yml"

# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

step="$(awk '/^      - name: Check each skipped lane against scope$/ { on = 1; print; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on && /^[[:blank:]]*$/ { print ""; next }
  on { exit }' <<<"$step" >"$TMP_ROOT/body.sh"

if [[ ! -s "$TMP_ROOT/body.sh" ]]; then
  fail "no 'Check each skipped lane against scope' step with a run: | body in $WORKFLOW"
  test_harness::report
  exit 1
fi
for line in "id: lanes" "LANES: \${{ toJSON(needs) }}" "if: \${{ !cancelled() }}"; do
  if [[ "$step" == *"$line"* ]]; then ok "step carries '$line'"; else fail "step lost '$line'"; fi
done
# shellcheck disable=SC2016 # a workflow literal to match, not a shell expansion
if grep -q 'results: \${{ steps.lanes.outputs.results }}' "$WORKFLOW"; then
  ok "the aggregate reads the checked results"
else
  fail "the aggregate does not read steps.lanes.outputs.results"
fi

lanes() {
  printf '{"select-tests":{"result":"%s","outputs":{"run_bash":"%s","run_python":"%s","run_node":"%s","run_shell":"%s"}},' "$1" "$2" "$3" "$4" "${8-true}"
  printf '"lint-repo":{"result":"success","outputs":{}},"lint-shell":{"result":"%s","outputs":{}},' "${9-success}"
  printf '"test-bash":{"result":"%s","outputs":{}},"test-python":{"result":"%s","outputs":{}},' "$5" "$6"
  printf '"test-node":{"result":"%s","outputs":{}}}' "$7"
}

expect() {
  local out rc got
  : >"$TMP_ROOT/out"
  out="$(LANES="$4" GITHUB_OUTPUT="$TMP_ROOT/out" bash -e "$TMP_ROOT/body.sh" 2>&1)" && rc=0 || rc=$?
  got="$(sed -n 's/^results=//p' "$TMP_ROOT/out")"
  if [[ "$2" == nonzero && "$rc" -ne 0 && -z "$got" ]]; then
    ok "$1"
  elif [[ "$2" == nonzero || "$rc" -ne "$2" ]]; then
    fail "$1: expected rc=$2 got rc=$rc out='$out'"
  elif [[ "$got" != "$3" ]]; then
    fail "$1: expected results '$3' got '$got'"
  else
    ok "$1"
  fi
}

expect "lanes with no work skip and pass" 0 "success success success success success success" \
  "$(lanes success false false false skipped skipped skipped false skipped)"
expect "a lane that ran keeps its result" 0 "success success failure failure success success" \
  "$(lanes success true false false failure skipped skipped true failure)"
expect "a skip where scope said work stays skipped" 0 "success success skipped skipped success success" \
  "$(lanes success true false false skipped skipped skipped true skipped)"
expect "a skip behind a failed scope stays skipped" 0 "failure success skipped skipped skipped skipped" \
  "$(lanes failure false false false skipped skipped skipped false skipped)"
expect "an empty row is not 'false'" 0 "success success skipped skipped skipped skipped" \
  "$(lanes success "" "" "" skipped skipped skipped "" skipped)"
expect "a skipped lane that is not test-<x> or lint-shell stays skipped" 0 "success skipped success success success success" \
  "$(lanes success false false false skipped skipped skipped | sed 's/"lint-repo":{"result":"success"/"lint-repo":{"result":"skipped"/')"
expect "lint-repo does not borrow a run_repo row" 0 "success skipped success success success success" \
  "$(lanes success false false false skipped skipped skipped | sed 's/"lint-repo":{"result":"success"/"lint-repo":{"result":"skipped"/; s/"run_shell"/"run_repo":"false","run_shell"/')"
expect "a contract-only run passes every skip through" 0 "skipped skipped skipped skipped skipped skipped" \
  "$(lanes skipped "" "" "" skipped skipped skipped "" skipped | sed 's/"lint-repo":{"result":"success"/"lint-repo":{"result":"skipped"/')"
expect "unreadable lanes fail and write no results" nonzero "" "not json"

check_tests() {
  printf '{"select-tests":{"result":"%s","outputs":{"run_check_tests":"%s","run_tests":"false"}},' "$1" "$2"
  printf '"check-plugins":{"result":"%s","outputs":{}},"check-tests":{"result":"%s","outputs":{}}}' "${4-success}" "$3"
}
expect "check-tests skipped beside a diff base passes" 0 "success success success" \
  "$(check_tests success false skipped)"
expect "check-tests skipped with no diff base stays skipped" 0 "success success skipped" \
  "$(check_tests success true skipped)"
expect "check-tests that ran keeps its failure" 0 "success success failure" \
  "$(check_tests success true failure)"
expect "check-tests with an empty row stays skipped" 0 "success success skipped" \
  "$(check_tests success "" skipped)"
expect "check-tests skipped behind a failed scope stays skipped" 0 "failure success skipped" \
  "$(check_tests failure false skipped)"
expect "check-plugins does not borrow a row" 0 "success skipped success" \
  "$(check_tests success false skipped skipped | sed 's/"check-tests":{"result":"skipped"/"check-tests":{"result":"success"/; s/"run_tests"/"run_plugins":"false","run_check_plugins":"false","run_tests"/')"

selection() {
  printf '{"select-tests":{"result":"%s","outputs":{"run_selection":"%s"}},"test-selection":{"result":"%s","outputs":{}}}' "$1" "$2" "$3"
}
expect "test-selection skipped on a change with no suite passes" 0 "success success" \
  "$(selection success false skipped)"
expect "test-selection skipped where suites changed stays skipped" 0 "success skipped" \
  "$(selection success true skipped)"
expect "test-selection that found a gap keeps its failure" 0 "success failure" \
  "$(selection success true failure)"

for line in "      run_check_tests: \${{ steps.base.outputs.ref == '' }}" \
  "&& needs.select-tests.outputs.run_check_tests == 'true' }}" \
  "&& needs.select-tests.outputs.run_selection == 'true' }}"; do
  if grep -qF -- "$line" "$WORKFLOW"; then ok "the workflow carries '$line'"; else fail "the workflow lost '$line'"; fi
done

shard_step="$(awk '/^      - name: Shard the listed suites$/ { on = 1; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
awk '/^        run: \|$/ { on = 1; next }
  on && /^          / { print substr($0, 11); next }
  on { exit }' <<<"$shard_step" >"$TMP_ROOT/shards.sh"
per_shard="$(sed -n 's/^          PER_SHARD: \([0-9][0-9]*\)$/\1/p' <<<"$shard_step")"
shards_for() {
  : >"$TMP_ROOT/shards.out"
  SUITES="$(jq -nc --argjson n "$1" '[range($n) | "s\(.).test.sh"]')" PER_SHARD="$per_shard" \
    GITHUB_OUTPUT="$TMP_ROOT/shards.out" bash -e "$TMP_ROOT/shards.sh" >/dev/null 2>&1 &&
    sed -n 's/^list=//p' "$TMP_ROOT/shards.out" | jq -c '[length, .[0], .[-1]]'
}
if [[ -n "$per_shard" && "$(shards_for 1)" == "[1,0,0]" && "$(shards_for "$per_shard")" == "[1,0,0]" &&
  "$(shards_for $((per_shard + 1)))" == "[2,0,1]" && "$(shards_for 125)" == "[$(((125 + per_shard - 1) / per_shard)),0,$(((125 + per_shard - 1) / per_shard - 1))]" &&
  "$(shards_for $((per_shard * 300)))" == "[256,0,255]" ]]; then
  ok "select-tests shards the listed suites: one shard up to PER_SHARD ($per_shard), more past it, and at most 256"
else
  fail "the shard step gave 1:[$(shards_for 1)] $((per_shard + 1)):[$(shards_for $((per_shard + 1)))] 125:[$(shards_for 125)] $((per_shard * 300)):[$(shards_for $((per_shard * 300)))]"
fi
for line in "        shard: \${{ fromJSON(needs.select-tests.outputs.selection_shards || '[0]') }}" \
  "      SHARD: \${{ strategy.job-index }}" "      SHARDS: \${{ strategy.job-total }}" \
  "          name: selection-trace-\${{ github.run_id }}-\${{ github.run_attempt }}-\${{ strategy.job-index }}"; do
  if grep -qxF -- "$line" "$WORKFLOW"; then ok "test-selection carries '$line'"; else fail "test-selection lost '$line'"; fi
done
if grep -qxF -- "          pattern: selection-trace-\${{ steps.locate.outputs.run-id }}-\${{ steps.locate.outputs.run-attempt }}-*" \
  "$ROOT/.github/workflows/pr-unblock.yml"; then
  ok "pr-unblock downloads every shard's trace artifact"
else
  fail "pr-unblock's trace download does not match the shard artifacts"
fi

trace_step="$(awk '/^      - name: Trace the changed suites$/ { on = 1; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
# shellcheck disable=SC2016 # a workflow literal to match, not a shell expansion
if grep -qE 'selection-audit\.sh trace --strict --shard "\$SHARD/\$SHARDS" .*--budget [0-9]+' <<<"$trace_step" &&
  [[ "$(grep -v '^[[:space:]]*$' <<<"$trace_step" | tail -n1)" == "          exit \"\$rc\"" ]] &&
  ! grep -qE 'exit 0|\|\| true' <<<"$trace_step"; then
  ok "test-selection traces its shard with --strict and a --budget, and exits with the trace's own status"
else
  fail "test-selection's trace step lost --strict, --shard, its --budget or its closing exit \"\$rc\": [$trace_step]"
fi

test_harness::report
