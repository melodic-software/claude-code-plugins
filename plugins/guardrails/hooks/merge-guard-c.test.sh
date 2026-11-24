#!/usr/bin/env bash

# shellcheck disable=SC2016
set -uo pipefail

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
# shellcheck source=merge-guard-fixtures.sh
source "$(dirname "${BASH_SOURCE[0]}")/merge-guard-fixtures.sh"

thread_page() {
  local resolved="$1" next="$2"
  jq -n --argjson r "$resolved" --arg next "$next" '{data: {repository: {pullRequest: {reviewThreads: {
    pageInfo: {hasNextPage: ($next != ""), endCursor: (if $next == "" then null else $next end)},
    nodes: [{isResolved: $r, path: "src/page.py", line: 7, originalLine: 7,
      comments: {nodes: [{body: "P1: on the second page", url: "https://github.com/acme/widgets/pull/42#discussion_r9"}]}}]}}}}}'
}

scenario none none green green
thread_page true p2 >"$FIX/graphql_threads.json"
thread_page false "" >"$FIX/graphql_threads_p2.json"
rm -f "$FIX/ccr.json"
run "an unresolved thread past the first 100 blocks" 'gh pr merge 42' 2
assert_contains "the second page's thread is listed" "$ERR" "src/page.py:7"
assert_eq "both thread pages are read" 2 "$(grep -c '^graphql$' "$FIX/calls")"

scenario none none green green
thread_page true p2 >"$FIX/graphql_threads.json"
thread_page true "" >"$FIX/graphql_threads_p2.json"
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
  jq -n --arg finished "$1" '{total_count: 1, check_runs: [{id: 901, name: "CI Status", app: {id: 15368, slug: "github-actions"},
    status: "completed", conclusion: "success", completed_at: $finished}]}' >"$FIX/checks.json"
}

pv_judged 2026-01-01T00:00:00Z
run "no pr-verify verdict 30 minutes after the checks finished: the merge goes ahead" 'gh pr merge 42' 0
assert_contains "past the wait -> says no verdict was read" "$OUT" "goes ahead without one"

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
