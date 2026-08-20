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

[[ $FAILED -eq 0 ]] || exit 1
