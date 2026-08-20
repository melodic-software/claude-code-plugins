#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# add-sub-item: offline contract tests.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/add-sub-item.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "linear:acme/ENG#20"
assert_usage_error "$S" "linear:acme/ENG#20" --parent
assert_usage_error "$S" "not-an-id" --parent "linear:acme/ENG#12"
assert_usage_error "$S" "linear:acme/ENG#20" --parent "not-an-id"
assert_usage_error "$S" "github:o/r#1" --parent "linear:acme/ENG#12"
# An item cannot be its own parent.
assert_usage_error "$S" "linear:acme/ENG#20" --parent "linear:acme/ENG#20"

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

# --- both ends face the authorization boundary ---
lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#1" --parent "linear:acme/ENG#12")"
assert_eq "out-of-scope child → exit 2" "2" "$rc"
assert_eq "nothing was requested" "" "$(lin_requests)"

# --- happy path ---
lin_reset
lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 20 started)" \
  '{issues: {nodes: [($i | .id = "uuid-issue-20")]}}')"
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" \
  '{issues: {nodes: [($i | .id = "uuid-issue-12")]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#20" --parent "linear:acme/ENG#12")"
assert_eq "link under a parent → exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_eq "id is the child" "linear:acme/ENG#20" "$(jq -r '.id' <<<"$(lin_out)")"
assert_eq "parent_id is the container" "linear:acme/ENG#12" "$(jq -r '.parent_id' <<<"$(lin_out)")"
assert_eq "linked" "true" "$(jq -r '.linked' <<<"$(lin_out)")"
# The CHILD is the mutation's subject and the parent is the value.
assert_contains "the child is the update subject" "$(lin_bodies)" '"id":"uuid-issue-20"'
assert_contains "the parent is the value" "$(lin_bodies)" '"parentId":"uuid-issue-12"'

# --- an immediate cycle is refused with a message about the cycle ---
# Linear rejects it too, but catching it here keeps the diagnostic about the request
# rather than about the provider's error text.
lin_reset
lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 20 started)" \
  '{issues: {nodes: [($i | .id = "uuid-issue-20")]}}')"
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" \
  '{issues: {nodes: [($i | .id = "uuid-issue-12" | .parent = {identifier: "ENG-20", team: {key: "ENG"}, number: 20})]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#20" --parent "linear:acme/ENG#12")"
assert_eq "an immediate parent cycle → exit 2" "2" "$rc"
assert_contains "and names the cycle" "$(lin_err)" "cycle"

# --- a missing endpoint is exit 5 ---
lin_reset
lin_data 'issues(filter:' '{"issues":{"nodes":[]}}'
rc="$(lin_run "$S" "linear:acme/ENG#20" --parent "linear:acme/ENG#12")"
assert_eq "missing child → exit 5" "5" "$rc"

[[ $FAILED -eq 0 ]] || exit 1
