#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/link-blocks.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

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

lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#1" --blocked-by "linear:acme/ENG#4")"
assert_eq "out-of-scope target → exit 2" "2" "$rc"
assert_eq "nothing was requested" "" "$(lin_requests)"
lin_reset
lin_seed_issue 12 started
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/OPS#4")"
assert_eq "out-of-scope blocker → exit 2" "2" "$rc"
assert_contains "the refusal names the blocker's team" "$(lin_err)" "acme/OPS"

lin_reset
lin_data 'issueRelationCreate' '{"issueRelationCreate":{"success":true}}'
lin_seed_issue 12 started
lin_seed_issue 4 started
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/ENG#4")"
assert_eq "link → exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_eq "id is the blocked item" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"
assert_eq "blocked_by is the blocker" "linear:acme/ENG#4" "$(jq -r '.blocked_by' <<<"$(lin_out)")"
assert_eq "linked" "true" "$(jq -r '.linked' <<<"$(lin_out)")"
assert_contains "the blocker is the relation source" "$(lin_bodies)" '"issueId":"uuid-issue-4"'
assert_contains "the blocked item is the relation target" "$(lin_bodies)" '"relatedIssueId":"uuid-issue-12"'
assert_contains "the relation type is blocks" "$(lin_bodies)" '"type":"blocks"'

lin_write_binding '{"scopes":["acme/ENG","acme/OPS"]}'
lin_reset
lin_data 'issueRelationCreate' '{"issueRelationCreate":{"success":true}}'
lin_seed_issue 12 started
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 7 started)" \
  '{issues: {nodes: [($i | .id = "uuid-issue-ops-7" | .team.key = "OPS")]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/OPS#7")"
assert_eq "cross-team link → exit 0" "0" "$rc"
assert_eq "blocked_by names the other team" "linear:acme/OPS#7" "$(jq -r '.blocked_by' <<<"$(lin_out)")"
lin_write_binding

lin_reset
lin_data 'issues(filter:' '{"issues":{"nodes":[]}}'
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/ENG#4")"
assert_eq "missing target issue → exit 5" "5" "$rc"

lin_reset
lin_seed 'issueRelationCreate' 200 '{"errors":[{"message":"nope","extensions":{"type":"AuthenticationError"}}]}'
lin_seed_issue 12 started
lin_seed_issue 4 started
rc="$(lin_run "$S" "linear:acme/ENG#12" --blocked-by "linear:acme/ENG#4")"
assert_eq "GraphQL auth error → exit 4" "4" "$rc"

[[ $FAILED -eq 0 ]] || exit 1
