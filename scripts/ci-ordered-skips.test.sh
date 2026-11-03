#!/usr/bin/env bash
# Runs the `Check each skipped lane against scope` step body of
# .github/workflows/pr-require-checks.yml's ci-status under the shell Actions gives a step with
# no `shell:` (bash -e), against `toJSON(needs)` fixtures.
#
# A test lane `test-<x>`, or `lint-shell` on `run_shell`, that skipped turns
# into `success` only where `select-tests` succeeded and its row is exactly
# 'false'. Every other result passes
# through unchanged, so a skip that hid work stays `skipped` and the aggregate
# (treat-skipped-as: fail) reds it.
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

# A lane cancelled after its steps finished. The stub stands in for the jobs read: it prints
# GH_FIXTURE, or fails on GH_FIXTURE=fail, and records that it was called.
mkdir -p "$TMP_ROOT/bin"
cat >"$TMP_ROOT/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo called >>"$GH_CALLS"
[[ "$GH_FIXTURE" == fail ]] && exit 1
printf '%s\n' "$GH_FIXTURE"
STUB
chmod +x "$TMP_ROOT/bin/gh"
export GH_CALLS="$TMP_ROOT/gh-calls" GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=1 GITHUB_RUN_ATTEMPT=1

# job <name> <conclusion> <other-step> <lane-finished-step> [<last-step-name>]
job() {
  printf '{"name":"%s","conclusion":"%s","steps":[{"name":"Run","conclusion":"%s"},{"name":"Lane finished","conclusion":"%s"},{"name":"%s","conclusion":"success"}]}\n' "$1" "$2" "$3" "$4" "${5-Complete job}"
}

# expect_cancelled <label> <want-results> <lanes-json> <fixture> [<want-notice>]
expect_cancelled() {
  local out got
  : >"$TMP_ROOT/out"
  out="$(PATH="$TMP_ROOT/bin:$PATH" GH_FIXTURE="$4" LANES="$3" GITHUB_OUTPUT="$TMP_ROOT/out" bash -e "$TMP_ROOT/body.sh" 2>&1)" || {
    fail "$1: step failed: $out"
    return
  }
  got="$(sed -n 's/^results=//p' "$TMP_ROOT/out")"
  if [[ "$got" != "$2" ]]; then
    fail "$1: expected results '$2' got '$got'"
  elif [[ -n "${5-}" && "$out" != *"$5"* ]]; then
    fail "$1: no notice '$5' in '$out'"
  else
    ok "$1"
  fi
}

cancelled_python="$(lanes success false true false skipped cancelled skipped false skipped)"
passed="success success success success success success"
kept="success success success success cancelled success"
expect_cancelled "every step finished: the lane counts as passed, with a notice" "$passed" "$cancelled_python" \
  "$(job 'test-python (0)' cancelled success success)" "lane=test-python counted-as-passed=true"
expect_cancelled "a limit between two steps skips Lane finished: the lane stays cancelled" "$kept" "$cancelled_python" \
  "$(job 'test-python (0)' cancelled success skipped)" "lane=test-python counted-as-passed=false"
expect_cancelled "a later step skipped on its own condition still counts as passed" "$passed" "$cancelled_python" \
  "$(job 'test-python (0)' cancelled skipped success)"
expect_cancelled "a job with no Lane finished step stays cancelled" "$kept" "$cancelled_python" \
  '{"name":"test-python (0)","conclusion":"cancelled","steps":[{"name":"Run","conclusion":"success"},{"name":"Complete job","conclusion":"success"}]}'
expect_cancelled "a skipped job with no steps stays cancelled" "$kept" "$cancelled_python" \
  '{"name":"test-python (0)","conclusion":"skipped","steps":[]}'
expect_cancelled "a step cancelled mid-run stays cancelled" "$kept" "$cancelled_python" \
  "$(job 'test-python (0)' cancelled cancelled skipped)"
expect_cancelled "a failed step stays cancelled" "$kept" "$cancelled_python" \
  "$(job 'test-python (0)' cancelled failure success)"
expect_cancelled "no Complete job stays cancelled" "$kept" "$cancelled_python" \
  "$(job 'test-python (0)' cancelled success success 'Post Run')"
expect_cancelled "a matrix sibling that failed keeps the lane cancelled" "$kept" "$cancelled_python" \
  "$(job 'test-python (0)' cancelled success success; job 'test-python (1)' failure failure skipped)"
expect_cancelled "every cancelled matrix sibling must have finished" "$kept" "$cancelled_python" \
  "$(job 'test-python (0)' cancelled success success; job 'test-python (1)' cancelled success skipped)"
expect_cancelled "a job read that fails leaves the lane cancelled" "$kept" "$cancelled_python" fail \
  "lane=test-python counted-as-passed=false"
expect_cancelled "a lane with no job in the read stays cancelled" "$kept" "$cancelled_python" \
  "$(job 'test-node' cancelled success success)"
expect_cancelled "another lane's name prefix does not match" "$kept" "$cancelled_python" \
  "$(job 'test-python-extra' cancelled success success)"
# select-tests finished but hung: its dependents never ran, so the run stays red on them.
expect_cancelled "a recovered select-tests does not excuse the lanes it blocked" \
  "success skipped skipped skipped skipped skipped" \
  "$(lanes cancelled "" "" "" skipped skipped skipped "" skipped | sed 's/"lint-repo":{"result":"success"/"lint-repo":{"result":"skipped"/')" \
  "$(job select-tests cancelled success success)"

: >"$GH_CALLS"
expect_cancelled "no cancelled lane makes no API call" \
  "success success failure failure success success" \
  "$(lanes success true false false failure skipped skipped true failure)" "$(job x success success success)"
if [[ -s "$GH_CALLS" ]]; then fail "gh was called with no cancelled lane"; else ok "gh is not called with no cancelled lane"; fi

# Every lane ci-status needs ends in Lane finished, so the rule above can pass it.
while read -r lane; do
  last="$(awk -v job="  $lane:" '$0 == job { on = 1; next } on && /^  [a-z]/ { exit } on && /^      - name: / { sub(/^      - name: /, ""); name = $0 } END { print name }' "$WORKFLOW")"
  if [[ "$last" == "Lane finished" ]]; then ok "$lane ends in Lane finished"; else fail "$lane ends in '$last'"; fi
done < <(awk '/^  ci-status:$/ { on = 1; next } on && /^    needs:$/ { n = 1; next } n && /^      - / { print $2; next } n { exit }' "$WORKFLOW")

test_harness::report
