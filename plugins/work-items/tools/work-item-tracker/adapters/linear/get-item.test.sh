#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# get-item: offline contract tests. The happy path drives the REAL normalizer against a
# canned Linear issue through a mocked curl — no live Linear call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/get-item.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "not-an-id"
assert_usage_error "$S" "#12"
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "linear:acme/ENG#12" extra

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

# --- the declared scope is an authorization boundary ---
rc="$(lin_run "$S" "linear:acme/OPS#5")"
assert_eq "an undeclared team is refused → exit 2" "2" "$rc"
assert_contains "the refusal names config.linear.scopes" "$(lin_err)" "config.linear.scopes"
assert_eq "and no request was made" "" "$(lin_requests)"

# --- happy path ---
lin_reset
lin_seed_issue 12 started
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "get-item exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
# The id is rebuilt from team key + number, NOT from the UUID: no URL resolves a UUID,
# and it is unreadable in a tracker comment.
assert_eq "id is fully qualified from team+number" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"
assert_eq "title" "a real issue" "$(jq -r '.title' <<<"$(lin_out)")"
assert_eq "assignee becomes a one-element array" "kyle" "$(jq -r '.assignees[0]' <<<"$(lin_out)")"
assert_eq "exactly one assignee (linear's field is singular)" "1" "$(jq -r '.assignees | length' <<<"$(lin_out)")"
assert_eq "labels are names" "type: fix" "$(jq -r '.labels[0]' <<<"$(lin_out)")"
assert_eq "url" "https://linear.app/acme/issue/ENG-12" "$(jq -r '.url' <<<"$(lin_out)")"
assert_eq "type is null (linear has no issue-type axis)" "null" "$(jq -r '.type' <<<"$(lin_out)")"
assert_eq "no parent → parent_id null" "null" "$(jq -r '.parent_id' <<<"$(lin_out)")"
assert_eq "body is not carried through the seam" "null" "$(jq -r '.description' <<<"$(lin_out)")"

# --- state classification is on WorkflowState.type, never .name ---
# `name` is user-renameable per team; `type` is the stable axis. Classifying on name
# would break the moment a team renamed "Done" to "Shipped".
for st in triage backlog unstarted started; do
  lin_reset
  lin_seed_issue 12 "$st"
  lin_run "$S" "linear:acme/ENG#12" >/dev/null
  assert_eq "state type '$st' normalizes to open" "open" "$(jq -r '.state' <<<"$(lin_out)")"
done
for st in completed canceled duplicate; do
  lin_reset
  lin_seed_issue 12 "$st"
  lin_run "$S" "linear:acme/ENG#12" >/dev/null
  assert_eq "state type '$st' normalizes to closed" "closed" "$(jq -r '.state' <<<"$(lin_out)")"
done

# The classification is config, not a constant — the same override seam jira gives its
# statusCategory keys, so a workspace with different conventions is not stuck.
lin_write_binding '{"done_state_types":["canceled"]}'
lin_reset
lin_seed_issue 12 completed
lin_run "$S" "linear:acme/ENG#12" >/dev/null
assert_eq "done_state_types override reclassifies completed as open" "open" "$(jq -r '.state' <<<"$(lin_out)")"
lin_reset
lin_seed_issue 12 canceled
lin_run "$S" "linear:acme/ENG#12" >/dev/null
assert_eq "and keeps canceled closed" "closed" "$(jq -r '.state' <<<"$(lin_out)")"
# An empty override would classify every state as open, so a claimed item's completion
# would never reach the frontier. Refused as a config error.
lin_write_binding '{"done_state_types":[]}'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "empty done_state_types → exit 3" "3" "$rc"
lin_write_binding

# --- blocked_by_count reads inverseRelations, and counts OPEN blockers only ---
# `relations` is the opposite direction; using it would invert every dependency edge.
lin_reset
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" \
  '{issues: {nodes: [($i | .inverseRelations.nodes = [
      {type: "blocks", issue: {state: {type: "started"}}},
      {type: "blocks", issue: {state: {type: "completed"}}},
      {type: "related", issue: {state: {type: "started"}}},
      {type: "blocks", issue: {state: {type: "backlog"}}}
    ])]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "blocked issue → exit 0" "0" "$rc"
# Two open `blocks` relations: the completed blocker and the `related` relation are both
# excluded. Counting the completed one is the bug that keeps an item off the frontier
# forever.
assert_eq "counts open blocks relations only" "2" "$(jq -r '.blocked_by_count' <<<"$(lin_out)")"

# --- parent_id is fully qualified ---
lin_reset
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" \
  '{issues: {nodes: [($i | .parent = {identifier: "ENG-3", team: {key: "ENG"}, number: 3})]}}')"
lin_run "$S" "linear:acme/ENG#12" >/dev/null
assert_eq "parent_id is fully qualified" "linear:acme/ENG#3" "$(jq -r '.parent_id' <<<"$(lin_out)")"

# --- a GraphQL error arrives with HTTP 200 and must NOT be treated as success ---
# This is the trap a REST-shaped transport check walks straight into.
lin_reset
lin_seed 'issues(filter:' 200 '{"data":null,"errors":[{"message":"Entity not found","extensions":{"type":"EntityNotFoundError"}}]}'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "GraphQL not-found inside a 200 → exit 5" "5" "$rc"
assert_contains "the provider's message is surfaced" "$(lin_err)" "Entity not found"

lin_reset
lin_seed 'issues(filter:' 200 '{"errors":[{"message":"key invalid","extensions":{"type":"AuthenticationError"}}]}'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "GraphQL auth error inside a 200 → exit 4" "4" "$rc"

lin_reset
lin_seed 'issues(filter:' 200 '{"errors":[{"message":"slow down","extensions":{"type":"ratelimited"}}]}'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "GraphQL rate limit inside a 200 → exit 8" "8" "$rc"

# An empty node list is a missing ITEM, not an empty success.
lin_reset
lin_data 'issues(filter:' '{"issues":{"nodes":[]}}'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "no matching issue → exit 5" "5" "$rc"

# --- HTTP-level status still maps ---
lin_reset
lin_seed 'issues(filter:' 401 '{"message":"unauthorized"}'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "HTTP 401 → exit 4" "4" "$rc"

lin_reset
lin_seed 'issues(filter:' 503 '{"message":"down"}'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "HTTP 503 → exit 8" "8" "$rc"

# --- the request goes to the one GraphQL endpoint, over https ---
lin_reset
lin_seed_issue 12 started
lin_run "$S" "linear:acme/ENG#12" >/dev/null
assert_contains "posts to the graphql endpoint" "$(lin_requests)" "https://api.linear.app/graphql"
# The team key and number travel as VARIABLES, not interpolated into the query text.
assert_contains "filter values travel as variables" "$(lin_bodies)" '"team":"ENG"'

[[ $FAILED -eq 0 ]] || exit 1
