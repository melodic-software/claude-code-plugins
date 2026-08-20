#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# link-blocks: offline contract tests. The case that matters most is DIRECTION — an
# inverted edge would make the frontier release exactly the items it should hold, and
# nothing would report an error.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/link-blocks.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "linear:acme/ENG#12"
assert_usage_error "$S" "linear:acme/ENG#12" --blocked-by
assert_usage_error "$S" "not-an-id" --blocked-by "linear:acme/ENG#4"
assert_usage_error "$S" "linear:acme/ENG#12" --blocked-by "not-an-id"
assert_usage_error "$S" "github:o/r#1" --blocked-by "linear:acme/ENG#4"
assert_usage_error "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/ENG#12"

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

# --- both ends face the authorization boundary ---
lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#1" --blocked-by "linear:acme/ENG#4")"
assert_eq "out-of-scope target → exit 2" "2" "$rc"
assert_eq "nothing was requested" "" "$(lin_requests)"
lin_reset
lin_seed_issue 12 started
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/OPS#4")"
assert_eq "out-of-scope blocker → exit 2" "2" "$rc"
assert_contains "the refusal names the blocker's team" "$(lin_err)" "acme/OPS"

# --- happy path: direction ---
# Linear documents IssueRelation.issue as "the source issue whose relationship is being
# described" and relatedIssue as the target. So `blocks` from the BLOCKER to the BLOCKED
# item is the edge this verb writes.
lin_reset
lin_data 'issueRelationCreate' '{"issueRelationCreate":{"success":true}}'
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" '{issues: {nodes: [$i]}}')"
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 4 started)" '{issues: {nodes: [($i | .id = "uuid-issue-4")]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/ENG#4")"
assert_eq "link → exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_eq "id is the blocked item" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"
assert_eq "blocked_by is the blocker" "linear:acme/ENG#4" "$(jq -r '.blocked_by' <<<"$(lin_out)")"
assert_eq "linked" "true" "$(jq -r '.linked' <<<"$(lin_out)")"
# The BLOCKER is the relation's source and the blocked item is its target.
assert_contains "the blocker is the relation source" "$(lin_bodies)" '"issueId":"uuid-issue-4"'
assert_contains "the blocked item is the relation target" "$(lin_bodies)" '"relatedIssueId":"uuid-issue-12"'
assert_contains "the relation type is blocks" "$(lin_bodies)" '"type":"blocks"'

# --- cross-team edges are allowed within the declared scope ---
lin_write_binding '{"scopes":["acme/ENG","acme/OPS"]}'
lin_reset
lin_data 'issueRelationCreate' '{"issueRelationCreate":{"success":true}}'
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" '{issues: {nodes: [$i]}}')"
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 7 started)" \
  '{issues: {nodes: [($i | .id = "uuid-issue-ops-7" | .team.key = "OPS")]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/OPS#7")"
assert_eq "cross-team link → exit 0" "0" "$rc"
assert_eq "blocked_by names the other team" "linear:acme/OPS#7" "$(jq -r '.blocked_by' <<<"$(lin_out)")"
lin_write_binding

# --- a missing endpoint is exit 5 ---
lin_reset
lin_data 'issues(filter:' '{"issues":{"nodes":[]}}'
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/ENG#4")"
assert_eq "missing target issue → exit 5" "5" "$rc"

# --- GraphQL errors inside a 200 still fail ---
lin_reset
lin_seed 'issueRelationCreate' 200 '{"errors":[{"message":"nope","extensions":{"type":"AuthenticationError"}}]}'
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" '{issues: {nodes: [$i]}}')"
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 4 started)" '{issues: {nodes: [$i]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/ENG#4")"
assert_eq "GraphQL auth error → exit 4" "4" "$rc"

[[ $FAILED -eq 0 ]] || exit 1
