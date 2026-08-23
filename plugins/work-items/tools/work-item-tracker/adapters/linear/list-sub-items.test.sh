#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# list-sub-items: offline contract tests.
#
# The invariant this verb must not break: it is a RAW enumeration. Closed children and
# nested containers are KEPT — the closed-children invariant check and sub-map traversal
# both need them, and frontier filtering is the separate core-side step.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-sub-items.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "not-an-id"
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "linear:acme/ENG#12" --state sideways

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

seed_children() {
  lin_reset
  lin_data 'children(' "$(jq -cn --argjson n "$1" --argjson h "${2:-false}" --arg c "${3:-}" \
    '{issue: {children: {nodes: $n, pageInfo: {hasNextPage: $h, endCursor: $c}}}}')"
  lin_seed_issue 12 started
}

# --- children are enumerated and carry the container as parent_id ---
seed_children "$(jq -cn --argjson a "$(lin_issue_json 20 started)" --argjson b "$(lin_issue_json 21 completed)" '[$a, $b]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "list-sub-items → exit 0" "0" "$rc"
assert_eq "envelope schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
# Default --state is `all`, and the CLOSED child is kept: dropping it would make the
# closed-children invariant check pass on a container that still has work under it.
assert_eq "both children returned by default" "2" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "the closed child is kept" "closed" "$(jq -r '[.items[] | select(.id == "linear:acme/ENG#21")][0].state' <<<"$(lin_out)")"
# Every child carries the CONTAINER as parent_id, whatever its own selection said.
assert_eq "first child's parent_id is the container" "linear:acme/ENG#12" "$(jq -r '.items[0].parent_id' <<<"$(lin_out)")"
assert_eq "second child's parent_id is the container" "linear:acme/ENG#12" "$(jq -r '.items[1].parent_id' <<<"$(lin_out)")"

# --- --state narrows ---
seed_children "$(jq -cn --argjson a "$(lin_issue_json 20 started)" --argjson b "$(lin_issue_json 21 completed)" '[$a, $b]')"
lin_run "$S" "linear:acme/ENG#12" --state open >/dev/null
assert_eq "--state open narrows to the open child" "1" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "and it is the open one" "linear:acme/ENG#20" "$(jq -r '.items[0].id' <<<"$(lin_out)")"

# --- a container with no children is an empty array, never an error ---
seed_children '[]'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "childless container → exit 0" "0" "$rc"
assert_eq "empty items array" "0" "$(jq -r '.items | length' <<<"$(lin_out)")"

# --- a MISSING container is exit 5, which is a different answer ---
lin_reset
lin_data 'issues(filter:' '{"issues":{"nodes":[]}}'
rc="$(lin_run "$S" "linear:acme/ENG#99")"
assert_eq "missing container → exit 5" "5" "$rc"

# --- pagination follows the cursor ---
lin_reset
lin_data 'children(' "$(jq -cn --argjson n "[$(lin_issue_json 20 started)]" \
  '{issue: {children: {nodes: $n, pageInfo: {hasNextPage: true, endCursor: "cursor-1"}}}}')"
lin_data 'children(' "$(jq -cn --argjson n "[$(lin_issue_json 21 started)]" \
  '{issue: {children: {nodes: $n, pageInfo: {hasNextPage: false, endCursor: ""}}}}')"
lin_seed_issue 12 started
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "paged children → exit 0" "0" "$rc"
assert_eq "both pages collected" "2" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_contains "the cursor is sent on the second call" "$(lin_bodies)" '"after":"cursor-1"'

# --- scope boundary ---
lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#5")"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_eq "and nothing was requested" "" "$(lin_requests)"

[[ $FAILED -eq 0 ]] || exit 1
