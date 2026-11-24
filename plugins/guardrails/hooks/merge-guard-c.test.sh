#!/usr/bin/env bash

# shellcheck disable=SC2016
set -uo pipefail

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# shellcheck source=merge-guard-fixtures.sh
source "$(dirname "${BASH_SOURCE[0]}")/merge-guard-fixtures.sh"

CAPTURED="$HOOK_DIR/fixtures"
thread_pages() {
  local t=.data.repository.pullRequest.reviewThreads cursor
  cursor="$(jq -r "$t.pageInfo.endCursor" "$CAPTURED/review-threads-page1.json")"
  jq --argjson r "$1" "$t.nodes[].isResolved = \$r" "$CAPTURED/review-threads-page1.json" >"$FIX/graphql_threads.json"
  jq --argjson r "$2" "$t.nodes[].isResolved = \$r | $t.pageInfo.hasNextPage = false" \
    "$CAPTURED/review-threads-page2.json" >"$FIX/graphql_threads_$cursor.json"
}

scenario none none green green
thread_pages true false
rm -f "$FIX/ccr.json"
run "an unresolved thread past the first 100 blocks" 'gh pr merge 42' 2
assert_contains "the second page's thread is listed" "$ERR" "lib/merge-readiness.sh:377"
assert_eq "both thread pages are read" 2 "$(grep -c '^graphql$' "$FIX/calls")"

scenario none none green green
thread_pages true true
run "every page resolved lets the merge run" 'gh pr merge 42' 0
assert_absent "every page resolved -> nothing unchecked" "$OUT" "will run unchecked"

scenario unresolved none green green
run "a refusal names the skill's merge path" 'gh pr merge 42' 2
assert_contains "refusal -> /source-control:pull-request merge" "$ERR" "/source-control:pull-request merge"

pv_judged() {
  scenario none none green green
  echo '{"state":"open","head":{"sha":"abc123","ref":"feat/x","repo":{"full_name":"acme/widgets"}},"base":{"ref":"main","repo":{"full_name":"acme/widgets","default_branch":"main"}},"user":{"id":9,"login":"kyle","type":"User"},"labels":[]}' >"$FIX/pr.json"
  local conf='merge:\n  verify-authors: lane-or-owner\n'
  printf '{"data":{"repository":{"w":{"oid":"f00"},"c":{"text":"%s"},"t":{"text":"{\\"actors\\":[{\\"id\\":9}]}"}}}}\n' "$conf" >"$FIX/graphql_scope.json"
  jq --arg finished "$1" '.check_runs[0].completed_at = $finished' "$CAPTURED/check-runs-ci-status.json" >"$FIX/checks.json"
}

pv_judged 2026-01-01T00:00:00Z
run "no pr-verify verdict 30 minutes after the checks finished: the merge goes ahead" 'gh pr merge 42' 0
assert_contains "past the wait -> says no verdict was read" "$OUT" "goes ahead without one"

pv_judged 2026-01-01T00:00:00Z
jq '.check_runs += [.check_runs[0] | .id += 1 | .name = "integration" | .status = "in_progress" | .conclusion = null | .completed_at = null]
  | .total_count = 2 | .check_runs[0].completed_at = "2026-01-01T00:00:00Z"' "$CAPTURED/check-runs-ci-status.json" >"$FIX/checks.json"
run "no pr-verify verdict and a check still running: --auto is refused" 'gh pr merge 42 --auto' 2
assert_contains "a check still running -> the wait has not started" "$ERR" "no pr-verify PASS or PASS-NOTES verdict at its head abc123"

pv_judged 2099-01-01T00:00:00Z
run "no pr-verify verdict inside the wait still blocks" 'gh pr merge 42' 2
assert_contains "inside the wait -> names the head" "$ERR" "no pr-verify PASS or PASS-NOTES verdict at its head abc123"

pv_judged 2026-01-01T00:00:00Z
echo '{"state":"open","head":{"sha":"abc123","ref":"feat/x","repo":{"full_name":"acme/widgets"}},"base":{"ref":"main","repo":{"full_name":"acme/widgets","default_branch":"main"}},"user":{"id":9,"login":"kyle","type":"User"},"labels":[{"name":"PR-Verify-Failed"}]}' >"$FIX/pr.json"
run "a pr-verify FAIL label outranks the no-verdict wait, in any case" 'gh pr merge 42' 2
assert_contains "FAIL label -> named as a hold" "$ERR" "Hold labels: PR-Verify-Failed"

echo
echo "merge-guard-c: $PASS passed, $FAIL failed"
((FAIL == 0))
