#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# list-items: offline contract tests. Pagination, state filtering, and the scope
# boundary are driven through a mocked curl — no live Linear call.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-items.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" --state
assert_usage_error "$S" --state sideways
assert_usage_error "$S" --repo

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

# --repo is caller text that reaches a request variable, so it faces the same anchored
# allowlist the binding's own scopes did, then the scope list itself.
rc="$(lin_run "$S" --repo "ENG")"
assert_eq "--repo without a workspace → exit 2" "2" "$rc"
rc="$(lin_run "$S" --repo "acme/eng")"
assert_eq "lowercase team key → exit 2" "2" "$rc"
rc="$(lin_run "$S" --repo "acme/OPS")"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_contains "refusal names the declared scope" "$(lin_err)" "config.linear.scopes"
assert_eq "and nothing was requested" "" "$(lin_requests)"

# seed_page <nodes-json> [has-next] [cursor]
seed_page() {
  lin_data 'issues(filter:' "$(jq -cn --argjson n "$1" --argjson h "${2:-false}" --arg c "${3:-}" \
    '{issues: {nodes: $n, pageInfo: {hasNextPage: $h, endCursor: $c}}}')"
}

# --- the declared scope is the default target ---
lin_reset
seed_page "[$(lin_issue_json 12 started)]"
rc="$(lin_run "$S")"
assert_eq "listing → exit 0" "0" "$rc"
assert_eq "envelope schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_eq "one item" "1" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "item id is fully qualified" "linear:acme/ENG#12" "$(jq -r '.items[0].id' <<<"$(lin_out)")"
# The team filter travels as a VARIABLE, never interpolated into the query text.
assert_contains "teams travel as a variable" "$(lin_bodies)" '"teams":["ENG"]'
assert_contains "an explicit page size is sent" "$(lin_bodies)" '"first":50'

# --- state filtering is core-side, on the SAME classification the normalizer uses ---
# Pushing it into the GraphQL filter would encode done_state_types a second time in a
# different language, and the two would drift.
lin_reset
seed_page "$(jq -cn --argjson o "$(lin_issue_json 12 started)" --argjson c "$(lin_issue_json 13 completed)" '[$o, $c]')"
rc="$(lin_run "$S" --state open)"
assert_eq "--state open → exit 0" "0" "$rc"
assert_eq "only the open item" "1" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_eq "and it is the open one" "linear:acme/ENG#12" "$(jq -r '.items[0].id' <<<"$(lin_out)")"

lin_reset
seed_page "$(jq -cn --argjson o "$(lin_issue_json 12 started)" --argjson c "$(lin_issue_json 13 completed)" '[$o, $c]')"
lin_run "$S" --state closed >/dev/null
assert_eq "--state closed returns only the closed item" "linear:acme/ENG#13" "$(jq -r '.items[0].id' <<<"$(lin_out)")"

lin_reset
seed_page "$(jq -cn --argjson o "$(lin_issue_json 12 started)" --argjson c "$(lin_issue_json 13 completed)" '[$o, $c]')"
lin_run "$S" --state all >/dev/null
assert_eq "--state all returns both" "2" "$(jq -r '.items | length' <<<"$(lin_out)")"

# The override reaches list filtering too, not just get-item.
lin_write_binding '{"done_state_types":["canceled"]}'
lin_reset
seed_page "[$(lin_issue_json 13 completed)]"
lin_run "$S" --state open >/dev/null
assert_eq "done_state_types override reclassifies for listing" "1" "$(jq -r '.items | length' <<<"$(lin_out)")"
lin_write_binding

# --- pagination follows the cursor ---
lin_reset
seed_page "[$(lin_issue_json 12 started)]" true "cursor-1"
seed_page "[$(lin_issue_json 13 started)]" false ""
rc="$(lin_run "$S")"
assert_eq "paged listing → exit 0" "0" "$rc"
assert_eq "both pages collected" "2" "$(jq -r '.items | length' <<<"$(lin_out)")"
assert_contains "the cursor is sent on the second call" "$(lin_bodies)" '"after":"cursor-1"'

# An empty result is an empty envelope, never an error.
lin_reset
seed_page '[]'
rc="$(lin_run "$S")"
assert_eq "no issues → exit 0" "0" "$rc"
assert_eq "empty items array" "0" "$(jq -r '.items | length' <<<"$(lin_out)")"

# --- multiple declared teams are all listed, and --repo narrows ---
lin_write_binding '{"scopes":["acme/ENG","acme/OPS"]}'
lin_reset
seed_page '[]'
lin_run "$S" >/dev/null
assert_contains "both declared teams are queried" "$(lin_bodies)" '"teams":["ENG","OPS"]'
lin_reset
seed_page '[]'
lin_run "$S" --repo "acme/OPS" >/dev/null
assert_contains "--repo narrows to one team" "$(lin_bodies)" '"teams":["OPS"]'
lin_write_binding

# --- a scopes list spanning two workspaces is a config error ---
# One API key reaches exactly one workspace, so such a binding describes something it
# cannot address — better refused than half-working.
lin_write_binding '{"scopes":["acme/ENG","other/OPS"]}'
lin_reset
rc="$(lin_run "$S")"
assert_eq "scopes across two workspaces → exit 3" "3" "$rc"
assert_contains "and says why" "$(lin_err)" "one workspace"
lin_write_binding

# --- GraphQL errors inside a 200 still fail ---
lin_reset
lin_seed 'issues(filter:' 200 '{"errors":[{"message":"nope","extensions":{"type":"AuthenticationError"}}]}'
rc="$(lin_run "$S")"
assert_eq "GraphQL auth error → exit 4" "4" "$rc"

[[ $FAILED -eq 0 ]] || exit 1
