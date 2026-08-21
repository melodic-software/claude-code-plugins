#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# create-item: offline contract tests. Label-name → label-id resolution, the parent
# link, and blocker edges are all driven through a mocked curl — no live Linear call.
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

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

TEAM_NODE='{"teams":{"nodes":[{"id":"uuid-team-eng"}]}}'
# Labels come from the ROOT issueLabels connection now, not team.labels — see the
# pagination/workspace-label cases below for why.
LABEL_PAGE='{"issueLabels":{"nodes":[{"id":"uuid-label-fix","name":"type: fix"},{"id":"uuid-label-hi","name":"priority: high"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}'

seed_create() {
  lin_reset
  lin_data 'issueRelationCreate' '{"issueRelationCreate":{"success":true}}'
  lin_data 'issueCreate' '{"issueCreate":{"success":true,"issue":{"id":"uuid-issue-12","number":12,"team":{"key":"ENG"}}}}'
  lin_data 'teams(filter:' "$TEAM_NODE"
  lin_data 'issueLabels(' "$LABEL_PAGE"
  lin_seed_issue 12 started
}

# --- happy path ---
seed_create
rc="$(lin_run "$S" --title "new work")"
assert_eq "create → exit 0" "0" "$rc"
assert_eq "returns the normalized item" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_contains "the team is resolved first" "$(lin_requests)" "teams(filter:"
assert_contains "the issue is created" "$(lin_requests)" "issueCreate"

# --- labels are resolved from NAMES to IDS ---
# Linear's IssueCreateInput takes `labelIds`, not names. Passing names would be
# accepted-looking and simply not apply.
seed_create
rc="$(lin_run "$S" --title "labelled" --labels "type: fix,priority: high")"
assert_eq "labelled create → exit 0" "0" "$rc"
assert_contains "label ids are sent, not names" "$(lin_bodies)" '"labelIds":["uuid-label-fix","uuid-label-hi"]'

# An unknown label is REFUSED, not dropped: an item filed without its type or priority
# label is invisible to the very selection tiers that would have picked it up.
seed_create
rc="$(lin_run "$S" --title "x" --labels "type: fix,nonexistent")"
assert_eq "unknown label → exit 5" "5" "$rc"
assert_contains "the missing label is named" "$(lin_err)" "nonexistent"
if [[ "$(lin_requests)" == *"issueCreate"* ]]; then
  fail "no issue is created when a label is unknown" "no issueCreate" "issueCreate issued"
else
  pass "no issue is created when a label is unknown"
fi

# --- --type cannot be honored, and says so ---
seed_create
rc="$(lin_run "$S" --title "typed" --type "Bug")"
assert_eq "--type is accepted → exit 0" "0" "$rc"
assert_contains "but reported as ignored" "$(lin_err)" "--type is ignored"
assert_eq "and type stays null" "null" "$(jq -r '.type' <<<"$(lin_out)")"

# --- the parent link rides in the CREATE input ---
# One fewer window in which a created item exists without its container.
seed_create
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "create with a parent → exit 0" "0" "$rc"
assert_contains "parentId is in the create input" "$(lin_bodies)" '"parentId":"uuid-issue-12"'

# --- ids are validated and RESOLVED before the item is created ---
# The links are separate operations, so a bad id found afterwards would leave a created
# item whose declared relationships were never written — an item that then looks ready.
lin_reset
rc="$(lin_run "$S" --title "t" --parent "not-an-id")"
assert_eq "malformed --parent → exit 2" "2" "$rc"
assert_eq "and nothing was created" "" "$(lin_requests)"
lin_reset
rc="$(lin_run "$S" --title "t" --blocked-by "linear:acme/OPS#1")"
assert_eq "out-of-scope blocker → exit 2" "2" "$rc"
assert_eq "still nothing created" "" "$(lin_requests)"

# --- blocker edges are written after creation, in the right direction ---
seed_create
rc="$(lin_run "$S" --title "blocked" --blocked-by "linear:acme/ENG#12")"
assert_eq "create with a blocker → exit 0" "0" "$rc"
# {issueId: BLOCKER, relatedIssueId: NEW} — the blocker is the relation's SOURCE.
# Reversing these would invert the edge and the frontier would release the wrong items.
assert_contains "the blocker is the relation source" "$(lin_bodies)" '"type":"blocks"'
assert_contains "and the new issue is the target" "$(lin_bodies)" '"relatedIssueId":"uuid-issue-12"'

# --- a missing team is exit 5, not a create against nothing ---
lin_reset
lin_data 'teams(filter:' '{"teams":{"nodes":[]}}'
rc="$(lin_run "$S" --title "t")"
assert_eq "unknown team → exit 5" "5" "$rc"

# --- ambiguity is refused rather than guessed ---
lin_write_binding '{"scopes":["acme/ENG","acme/OPS"]}'
lin_reset
rc="$(lin_run "$S" --title "t")"
assert_eq "no --repo with two declared teams → exit 2" "2" "$rc"
assert_contains "and says --repo is required" "$(lin_err)" "--repo is required"
assert_eq "nothing was requested" "" "$(lin_requests)"
lin_write_binding

# --- GraphQL errors inside a 200 still fail ---
lin_reset
lin_data 'teams(filter:' "$TEAM_NODE"
lin_seed 'issueCreate' 200 '{"errors":[{"message":"forbidden","extensions":{"type":"Forbidden"}}]}'
rc="$(lin_run "$S" --title "t")"
assert_eq "GraphQL forbidden → exit 4" "4" "$rc"

# --- label lookup PAGINATES ---
# The old shape asked team.labels(first: 250) once, with no pageInfo and no loop. 250 is
# Linear's per-page MAXIMUM, not a comfortable ceiling — so a workspace past that count lost
# labels, and because an unresolved name is refused, the symptom was a hard exit on a label
# that exists rather than a quietly dropped one. Routes sharing a pattern are call-ordered,
# so these two seedings are page 1 and page 2.
lin_reset
lin_data 'issueCreate' '{"issueCreate":{"success":true,"issue":{"id":"uuid-issue-12","number":12,"team":{"key":"ENG"}}}}'
lin_data 'teams(filter:' "$TEAM_NODE"
lin_data 'issueLabels(' '{"issueLabels":{"nodes":[{"id":"uuid-label-fix","name":"type: fix"}],"pageInfo":{"hasNextPage":true,"endCursor":"cur-1"}}}'
lin_data 'issueLabels(' '{"issueLabels":{"nodes":[{"id":"uuid-label-p2","name":"on: page-two"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}'
lin_seed_issue 12 started
rc="$(lin_run "$S" --title "paged" --labels "on: page-two")"
assert_eq "a label on page 2 resolves → exit 0" "0" "$rc"
assert_contains "and its id is sent" "$(lin_bodies)" '"labelIds":["uuid-label-p2"]'
assert_contains "the second page was requested with the cursor" "$(lin_bodies)" 'cur-1'

# --- WORKSPACE-level labels are reachable ---
# `Team.labels` is documented only as "Labels associated with the team", while IssueLabel.team
# says "If null, the label is a workspace-level label available to all teams" — and the ROOT
# issueLabels query is the one documented to return both. A workspace label is valid on this
# team's issues, so the old team-scoped lookup refused a label that would have applied.
lin_reset
lin_data 'issueCreate' '{"issueCreate":{"success":true,"issue":{"id":"uuid-issue-12","number":12,"team":{"key":"ENG"}}}}'
lin_data 'teams(filter:' "$TEAM_NODE"
lin_data 'issueLabels(' '{"issueLabels":{"nodes":[{"id":"uuid-label-ws","name":"workspace: wide"}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}'
lin_seed_issue 12 started
rc="$(lin_run "$S" --title "ws" --labels "workspace: wide")"
assert_eq "a workspace-level label resolves → exit 0" "0" "$rc"
assert_contains "the filter admits team-null labels" "$(lin_bodies)" 'null'
assert_contains "and the workspace label id is sent" "$(lin_bodies)" '"labelIds":["uuid-label-ws"]'

# A nullable endCursor with hasNextPage true must STOP, not restart from the beginning —
# without a cursor the next request repeats page 1 forever.
lin_reset
lin_data 'issueCreate' '{"issueCreate":{"success":true,"issue":{"id":"uuid-issue-12","number":12,"team":{"key":"ENG"}}}}'
lin_data 'teams(filter:' "$TEAM_NODE"
lin_data 'issueLabels(' '{"issueLabels":{"nodes":[{"id":"uuid-label-fix","name":"type: fix"}],"pageInfo":{"hasNextPage":true,"endCursor":null}}}'
lin_seed_issue 12 started
rc="$(lin_run "$S" --title "x" --labels "type: fix")"
assert_eq "a null endCursor terminates rather than looping" "0" "$rc"
assert_eq "and asked for labels exactly once" "1" "$(grep -c 'issueLabels(' <<<"$(lin_bodies)")"

[[ $FAILED -eq 0 ]] || exit 1
