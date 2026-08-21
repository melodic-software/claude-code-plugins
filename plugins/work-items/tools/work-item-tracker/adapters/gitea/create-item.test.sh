#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# create-item: offline contract tests. The label-name → label-id resolution and the
# blocker-edge writes are driven through a mocked curl — no live Gitea call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create-item.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" # no --title
assert_usage_error "$S" --title
assert_usage_error "$S" --title "t" --repo

gitea_fixture_init
trap 'rm -rf "$GITEA_FIX"' EXIT

# --parent asks for a link Gitea's Issue has no field for, and the manifest declares
# sub_items=false. Accepting it silently would report a created item whose stated
# parent does not exist.
rc="$(gitea_run "$S" --title "t" --parent "gitea:acme/webapp#1")"
assert_eq "--parent → exit 2" "2" "$rc"
assert_contains "and says why" "$(gitea_err)" "sub_items=false"
assert_eq "nothing was created" "" "$(gitea_requests)"

# A malformed blocker id is caught BEFORE the item is created: the edges are a second
# request, so discovering it afterwards would leave a created item whose declared
# blockers were never linked — an item that then looks ready.
rc="$(gitea_run "$S" --title "t" --blocked-by "not-an-id")"
assert_eq "malformed --blocked-by → exit 2" "2" "$rc"
assert_eq "and nothing was created" "" "$(gitea_requests)"
rc="$(gitea_run "$S" --title "t" --blocked-by "gitea:other/repo#1")"
assert_eq "out-of-scope blocker → exit 2" "2" "$rc"
assert_eq "still nothing created" "" "$(gitea_requests)"

# --- happy path ---
gitea_reset_routes
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues" 201 "$(gitea_issue_json 12 open 'new work')"
rc="$(gitea_run "$S" --title "new work")"
assert_eq "create → exit 0" "0" "$rc"
assert_eq "returns the normalized item" "gitea:acme/webapp#12" "$(jq -r '.id' <<<"$(gitea_out)")"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(gitea_out)")"
assert_contains "posted to the issues endpoint" "$(gitea_requests)" \
  "POST https://git.example.invalid/api/v1/repos/acme/webapp/issues"

# --- labels are resolved from NAMES to IDS ---
# Gitea's CreateIssueOption takes `labels: []int64`, not names — a real divergence from
# GitHub's API. Passing names through would be accepted-looking and simply not apply.
gitea_reset_routes
gitea_seed "/labels" 200 "$(jq -cn '[{id:3,name:"type: fix"},{id:9,name:"priority: high"}]')"
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues" 201 "$(gitea_issue_json 12 open 'labelled')"
rc="$(gitea_run "$S" --title "labelled" --labels "type: fix,priority: high")"
assert_eq "labelled create → exit 0" "0" "$rc"
assert_contains "the label set was fetched" "$(gitea_requests)" "/labels"

# An unknown label name is refused, not dropped: a work item filed without its priority
# or type label is invisible to the very tiers that would have selected it.
gitea_reset_routes
gitea_seed "/labels" 200 "$(jq -cn '[{id:3,name:"type: fix"}]')"
gitea_seed "/issues" 201 "$(gitea_issue_json 12 open 'x')"
rc="$(gitea_run "$S" --title "x" --labels "type: fix,nonexistent")"
assert_eq "unknown label → exit 5" "5" "$rc"
assert_contains "the missing label is named" "$(gitea_err)" "nonexistent"
if [[ "$(gitea_requests)" == *"POST"* ]]; then
  fail "no issue is created when a label is unknown" "no POST" "POST issued"
else
  pass "no issue is created when a label is unknown"
fi

# --- --type cannot be honored, and says so ---
# Gitea has no issue-type registry, so the normalized `type` is structurally null.
gitea_reset_routes
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues" 201 "$(gitea_issue_json 12 open 'typed')"
rc="$(gitea_run "$S" --title "typed" --type "Bug")"
assert_eq "--type is accepted → exit 0" "0" "$rc"
assert_contains "but reported as ignored" "$(gitea_err)" "--type is ignored"
assert_eq "and type stays null" "null" "$(jq -r '.type' <<<"$(gitea_out)")"

# --- blocker edges are written after creation ---
gitea_reset_routes
gitea_seed "/issues/12/dependencies" 201 "$(gitea_issue_json 4 open 'blocker')"
gitea_seed "/dependencies" 200 '[]'
gitea_seed "/issues" 201 "$(gitea_issue_json 12 open 'blocked')"
rc="$(gitea_run "$S" --title "blocked" --blocked-by "gitea:acme/webapp#4")"
assert_eq "create with a blocker → exit 0" "0" "$rc"
assert_contains "the dependency edge was posted" "$(gitea_requests)" \
  "POST https://git.example.invalid/api/v1/repos/acme/webapp/issues/12/dependencies"

# A failed edge write must NOT report a created-and-linked item: the caller has to
# learn the graph is incomplete.
gitea_reset_routes
gitea_seed "/issues/12/dependencies" 404 '{"message":"the issue does not exist"}'
gitea_seed "/issues" 201 "$(gitea_issue_json 12 open 'blocked')"
rc="$(gitea_run "$S" --title "blocked" --blocked-by "gitea:acme/webapp#4")"
assert_eq "failed edge write → non-zero" "5" "$rc"

# --- the post-create blocker-count read-back ---
# The POST already succeeded here, so the issue EXISTS on the server and only the
# read-back of its open-blocker count fails. Exit 2 would be the dangerous answer: it
# says "usage — bad args", and a caller that duly fixes its args and retries files a
# duplicate issue.
gitea_reset_routes
gitea_seed "/dependencies" 401 '{"message":"token required"}'
gitea_seed "/issues" 201 "$(gitea_issue_json 12 open 'created, count unreadable')"
rc="$(gitea_run "$S" --title "created, count unreadable")"
assert_eq "unreadable blocker count after create → exit 4, never 2" "4" "$rc"
assert_contains "the issue really was posted" "$(gitea_requests)" \
  "POST https://git.example.invalid/api/v1/repos/acme/webapp/issues"
# A non-zero exit here must not read as "nothing happened" — the id of the created item
# is the only thing standing between the caller and a duplicate.
assert_contains "stderr names the created item" "$(gitea_err)" "gitea:acme/webapp#12"
assert_contains "and says it was created" "$(gitea_err)" "WAS CREATED"
# The count has no honest substitute, so nothing is emitted rather than a 0 that would
# put a blocked item on the frontier.
assert_eq "no item object is emitted" "" "$(gitea_out)"
# Feeding jq an empty --argjson was how this failed before: raw jq usage text on stderr.
if [[ "$(gitea_err)" == *"jq --help"* ]]; then
  fail "no raw jq usage text leaks to stderr" "no jq usage text" "jq --help text present"
else
  pass "no raw jq usage text leaks to stderr"
fi

# work-loop routes "seam exit 8 → backoff-and-retry", so a 5xx must stay an 8 here too.
gitea_reset_routes
gitea_seed "/dependencies" 503 '{"message":"down"}'
gitea_seed "/issues" 201 "$(gitea_issue_json 12 open 'created, deps down')"
rc="$(gitea_run "$S" --title "created, deps down")"
assert_eq "unavailable blocker-count read after create → exit 8" "8" "$rc"
assert_contains "and still names the created item" "$(gitea_err)" "gitea:acme/webapp#12"

# --- HTTP status mapping on the create itself ---
gitea_reset_routes
gitea_seed "/issues" 403 '{"message":"no write access"}'
rc="$(gitea_run "$S" --title "t")"
assert_eq "forbidden → exit 4" "4" "$rc"

# 423 is Gitea's archived-repository response on write paths.
gitea_reset_routes
gitea_seed "/issues" 423 '{"message":"repo is archived"}'
rc="$(gitea_run "$S" --title "t")"
assert_eq "archived repo → exit 7" "7" "$rc"

# --- ORGANIZATION-WIDE labels resolve ---
# `GetLabelsByRepoID` backs /repos/{o}/{r}/labels with `WHERE repo_id = ?`, so an org label
# never appears there — yet `NewIssueWithIndex` accepts any label whose OrgID == repo.OwnerID.
# The old lookup therefore refused a label that would have applied, and the asymmetry was
# user-visible and backwards: get-item and list-items DO report org labels in `.labels[]`,
# so the tracker returned a name it would then refuse to write back.
gitea_reset_routes
gitea_seed_total "/repos/acme/webapp/labels" 200 '[{"id":1,"name":"type: fix"}]' 1
gitea_seed_total "/orgs/acme/labels" 200 '[{"id":9,"name":"priority: high"}]' 1
gitea_seed "/issues" 201 '{"number":7,"title":"t","state":"open","assignees":[],"labels":[],"html_url":"https://gitea.example/acme/webapp/issues/7","repository":{"full_name":"acme/webapp"}}'
rc="$(gitea_run "$S" --title "t" --labels "priority: high")"
assert_eq "an org-wide label resolves → exit 0" "0" "$rc"
assert_contains "the org label endpoint was consulted" "$(gitea_requests)" "/orgs/acme/labels"

# The org walk must honour X-Total-Count like the repo walk above it, not a
# largest-page-seen heuristic. Two things that heuristic got wrong, both asserted here:
# it always spent one extra request (the page that sets the baseline can never be shorter
# than it), and because this mock answers by URL substring rather than by call count, a
# same-sized second page kept it walking to the ceiling — reporting a truncation that had
# not happened and turning a genuinely-missing label into a misleading message.
gitea_reset_routes
gitea_seed_total "/repos/acme/webapp/labels" 200 '[{"id":1,"name":"type: fix"}]' 1
gitea_seed_total "/orgs/acme/labels" 200 '[{"id":9,"name":"priority: high"}]' 1
gitea_seed "/issues" 201 '{"number":7,"title":"t","state":"open","assignees":[],"labels":[],"html_url":"https://gitea.example/acme/webapp/issues/7","repository":{"full_name":"acme/webapp"}}'
rc="$(gitea_run "$S" --title "t" --labels "priority: high")"
assert_eq "the count is satisfied on page 1 → exit 0" "0" "$rc"
assert_eq "and exactly one org-label request was made" "1" \
  "$(grep -c '/orgs/acme/labels' <<<"$(gitea_requests)")"

# A user-owned repo has no organization: /orgs/<user>/labels answers 404, which is not an
# error — there are simply no org labels to merge. A repo label must still resolve.
gitea_reset_routes
gitea_seed_total "/repos/acme/webapp/labels" 200 '[{"id":1,"name":"type: fix"}]' 1
gitea_seed "/orgs/acme/labels" 404 '{"message":"user redirect does not exist"}'
gitea_seed "/issues" 201 '{"number":8,"title":"t","state":"open","assignees":[],"labels":[],"html_url":"https://gitea.example/acme/webapp/issues/8","repository":{"full_name":"acme/webapp"}}'
rc="$(gitea_run "$S" --title "t" --labels "type: fix")"
assert_eq "a 404 from /orgs is not an error → exit 0" "0" "$rc"

# And a name that exists in neither place is still refused, not silently dropped.
gitea_reset_routes
gitea_seed_total "/repos/acme/webapp/labels" 200 '[{"id":1,"name":"type: fix"}]' 1
gitea_seed_total "/orgs/acme/labels" 200 '[{"id":9,"name":"priority: high"}]' 1
rc="$(gitea_run "$S" --title "t" --labels "nonexistent")"
assert_eq "a label in neither scope → exit 5" "5" "$rc"
assert_contains "and it is named" "$(gitea_err)" "nonexistent"

[[ $FAILED -eq 0 ]] || exit 1
