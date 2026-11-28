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

HOOK_REAL="$HOOK"
paged_hook() {
  local dir="$TEST_TMPDIR/per-page-$1"
  mkdir -p "$dir"
  ln -sf "$HOOK_DIR/abort-boundary.sh" "$HOOK_DIR/hook-utils.sh" "$HOOK_DIR/merge-hold-labels.json" \
    "$HOOK_DIR/pr-verify-run.jq" "$HOOK_REAL" "$dir/"
  sed "s/^MG_PER_PAGE=100\$/MG_PER_PAGE=$1/" "$HOOK_DIR/merge-readiness.sh" >"$dir/merge-readiness.sh"
  assert_eq "the $1-per-page copy rewrote the page size" 1 "$(grep -c "^MG_PER_PAGE=$1\$" "$dir/merge-readiness.sh")"
  HOOK="$dir/merge-guard.sh"
}
review_pages() {
  scenario none none green green
  jq "$1" "$CAPTURED/reviews-page1.json" >"$FIX/reviews.json"
  jq "$2" "$CAPTURED/reviews-page2.json" >"$FIX/reviews_page2.json"
}

paged_hook 4
review_pages . '.[-1].state = "CHANGES_REQUESTED"'
run "a change request on the second page of reviews blocks" 'gh pr merge 42' 2
assert_contains "the second page's reviewer is named" "$ERR" "Changes requested by: kyle-sexton"
assert_contains "the second page of reviews was read" "$(calls)" "reviews?per_page=4&page=2"

review_pages '.[2].state = "CHANGES_REQUESTED"' '.[-1].state = "APPROVED"'
run "an approval on the second page clears that reviewer's earlier change request" 'gh pr merge 42' 0
assert_absent "a later approval -> nothing unchecked" "$OUT" "will run unchecked"

review_pages . .
rm "$FIX/reviews_page2.json"
run "a review list longer than the page cap lets the merge run unchecked" 'gh pr merge 42' 0
assert_contains "past the cap -> says so" "$OUT" "will run unchecked"
assert_contains "past the cap -> names the list" "$OUT" "more than 80 items at repos/acme/widgets/pulls/42/reviews"
assert_eq "past the cap -> 20 pages read, no more" 20 "$(grep -c '/reviews?' "$FIX/calls")"

paged_hook 32
scenario none none green green
cp "$CAPTURED/check-runs-page1.json" "$FIX/checks.json"
jq '(.check_runs[] | select(.name == "PR Review / Publish Review")).conclusion = "failure"' \
  "$CAPTURED/check-runs-page2.json" >"$FIX/checks_page2.json"
run "a failed check run on the second page blocks" 'gh pr merge 42' 2
assert_contains "the second page's check is named" "$ERR" "Failing checks: PR Review / Publish Review"
cp "$CAPTURED/check-runs-page2.json" "$FIX/checks_page2.json"
run "every page of check runs green lets the merge run" 'gh pr merge 42' 0
assert_absent "green pages -> nothing unchecked" "$OUT" "will run unchecked"

paged_hook 7
scenario none none green green
cp "$CAPTURED/status-page1.json" "$FIX/status.json"
jq '(.statuses[] | select(.context == "tide")).state = "failure"' "$CAPTURED/status-page2.json" >"$FIX/status_page2.json"
run "a failed commit status on the second page blocks" 'gh pr merge 42' 2
assert_contains "the second page's status is named" "$ERR" "Failing checks: tide"
HOOK="$HOOK_REAL"

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
