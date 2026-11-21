#!/usr/bin/env bash
# Runs the `Check each skipped lane against scope` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions gives a step with
# no `shell:` (bash -e), against `toJSON(needs)` fixtures.
# test-scope: .github/workflows/pr-require-checks.yml
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

# lanes <scope-result> <run_bash> <run_python> <run_node> <bash> <python> <node> [<run_shell> <lint-shell>]
lanes() {
  printf '{"select-tests":{"result":"%s","outputs":{"run_bash":"%s","run_python":"%s","run_node":"%s","run_shell":"%s"}},' "$1" "$2" "$3" "$4" "${8-true}"
  printf '"lint-repo":{"result":"success","outputs":{}},"lint-shell":{"result":"%s","outputs":{}},' "${9-success}"
  printf '"test-bash":{"result":"%s","outputs":{}},"test-python":{"result":"%s","outputs":{}},' "$5" "$6"
  printf '"test-node":{"result":"%s","outputs":{}}}' "$7"
}

# expect <label> <want-rc> <want-results> <lanes-json>
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

trace_step="$(awk '/^      - name: Trace the changed suites$/ { on = 1; next }
  on && /^      - / { exit }
  on { print }' "$WORKFLOW")"
if grep -qE 'selection-audit\.sh trace --strict .*--budget [0-9]+' <<<"$trace_step" &&
  [[ "$(grep -v '^[[:space:]]*$' <<<"$trace_step" | tail -n1)" == '          exit "$rc"' ]] &&
  ! grep -qE 'exit 0|\|\| true' <<<"$trace_step"; then
  ok "test-selection traces with --strict and a --budget, and exits with the trace's own status"
else
  fail "test-selection's trace step lost --strict, its --budget or its closing exit \"\$rc\": [$trace_step]"
fi

test_harness::report
