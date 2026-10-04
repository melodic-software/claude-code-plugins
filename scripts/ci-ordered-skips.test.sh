#!/usr/bin/env bash
# Runs the `Check each skipped lane against scope` step body of
# .github/workflows/ci.yml's ci-status under the shell Actions gives a step with
# no `shell:` (bash -e), against `toJSON(needs)` fixtures.
#
# A test lane `test-<x>`, or `lint-shell` on `run_shell`, that skipped turns
# into `success` only where `scope` succeeded and its row is exactly 'false'. Every other result passes
# through unchanged, so a skip that hid work stays `skipped` and the aggregate
# (treat-skipped-as: fail) reds it.
# test-scope: .github/workflows/ci.yml
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/ci.yml"

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
  printf '{"scope":{"result":"%s","outputs":{"run_bash":"%s","run_python":"%s","run_node":"%s","run_shell":"%s"}},' "$1" "$2" "$3" "$4" "${8-true}"
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

test_harness::report
