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

# seed_create [<children-nodes-json>]: the parent's children answer the sibling check, none by default.
seed_create() {
  lin_reset
  lin_data 'issueRelationCreate' '{"issueRelationCreate":{"success":true}}'
  lin_data 'issueCreate' '{"issueCreate":{"success":true,"issue":{"id":"uuid-issue-12","number":12,"team":{"key":"ENG"}}}}'
  lin_data 'teams(filter:' "$TEAM_NODE"
  lin_data 'issueLabels(' "$LABEL_PAGE"
  lin_seed_issue 12 started
  lin_data 'children(' "$(jq -cn --argjson n "${1:-[]}" \
    '{issue: {children: {nodes: $n, pageInfo: {hasNextPage: false, endCursor: null}}}}')"
}

# child_node <number> <state-type> <title> [<completedAt>]: a child as the sibling check selects it.
child_node() {
  jq -c --arg c "${4:-}" '. + {completedAt: (if ($c | length) > 0 then $c else null end), canceledAt: null}' \
    <<<"$(lin_issue_json "$1" "$2" "$3")"
}
HOUR_AGO="$(jq -rn 'now - 3600 | todate')"
TWO_DAYS_AGO="$(jq -rn 'now - 172800 | todate')"

assert_no_create() {
  if [[ "$(lin_requests)" == *"issueCreate"* ]]; then
    fail "$1" "no issueCreate" "issueCreate issued"
  else
    pass "$1"
  fi
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
rc="$(lin_run "$S" --title "labeled" --labels "type: fix,priority: high")"
assert_eq "labeled create → exit 0" "0" "$rc"
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

# --- a same-titled child of the parent is returned, not filed again (CONTRACT.md "Verbs") ---
# Open, with whitespace around the stored title: the match is exact after trimming both.
seed_create "[$(child_node 40 started '  child  ')]"
rc="$(lin_run "$S" --title "child " --parent "linear:acme/ENG#12")"
assert_eq "open same-titled child → exit 0" "0" "$rc"
assert_no_create "and no issue is created for an open sibling"
assert_eq "stdout is the existing child" "linear:acme/ENG#40" "$(jq -r '.id' <<<"$(lin_out)")"
assert_eq "carrying the parent" "linear:acme/ENG#12" "$(jq -r '.parent_id' <<<"$(lin_out)")"
assert_eq "as an open item" "open" "$(jq -r '.state' <<<"$(lin_out)")"
assert_contains "stderr names the child" "$(lin_err)" "linear:acme/ENG#40"

# Closed an hour ago by completedAt: still blocks.
seed_create "[$(child_node 41 completed child "$HOUR_AGO")]"
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "child completed 1h ago → exit 0" "0" "$rc"
assert_no_create "and no issue is created for a recently completed sibling"
assert_eq "stdout is the closed child" "linear:acme/ENG#41" "$(jq -r '.id' <<<"$(lin_out)")"

# Canceled an hour ago: canceledAt is the close time of the canceled state type.
seed_create "[$(jq -c --arg c "$HOUR_AGO" '. + {completedAt: null, canceledAt: $c}' <<<"$(lin_issue_json 42 canceled child)")]"
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "child canceled 1h ago → exit 0" "0" "$rc"
assert_no_create "and no issue is created for a recently canceled sibling"
assert_eq "stdout is the canceled child" "linear:acme/ENG#42" "$(jq -r '.id' <<<"$(lin_out)")"

# Completed two days ago, reopened, then canceled an hour ago: the later close time counts.
seed_create "[$(jq -c --arg d "$TWO_DAYS_AGO" --arg c "$HOUR_AGO" '. + {completedAt: $d, canceledAt: $c}' <<<"$(lin_issue_json 43 canceled child)")]"
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "child canceled 1h ago after an older completion → exit 0" "0" "$rc"
assert_no_create "and the older completion time does not let a duplicate through"

# An open match wins over a recently closed one, whatever the order.
seed_create "[$(child_node 41 completed child "$HOUR_AGO"),$(child_node 40 started child)]"
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "open and closed siblings → exit 0" "0" "$rc"
assert_eq "the open sibling is returned" "linear:acme/ENG#40" "$(jq -r '.id' <<<"$(lin_out)")"

# Closed two days ago: does not block.
seed_create "[$(child_node 41 completed child "$TWO_DAYS_AGO")]"
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "child completed 2 days ago → exit 0" "0" "$rc"
assert_contains "and a new issue is created" "$(lin_requests)" "issueCreate"
assert_eq "returning the new item" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"

# Closed with no readable close time counts as closed earlier.
seed_create "[$(child_node 41 completed child)]"
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "closed child with no close time → exit 0" "0" "$rc"
assert_contains "and a new issue is created over it" "$(lin_requests)" "issueCreate"

# A differently titled open child does not block.
seed_create "[$(child_node 40 started 'other work')]"
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "differently titled child → exit 0" "0" "$rc"
assert_contains "and a new issue is created beside it" "$(lin_requests)" "issueCreate"

# A match on the second children page still blocks: the walk follows endCursor. Routes
# sharing a pattern are call-ordered, so the second children seeding is page 2.
CHILDREN_P1="$(jq -cn --argjson n "[$(child_node 40 started 'other work')]" \
  '{issue: {children: {nodes: $n, pageInfo: {hasNextPage: true, endCursor: "c1"}}}}')"
CHILDREN_P2="$(jq -cn --argjson n "[$(child_node 44 started child)]" \
  '{issue: {children: {nodes: $n, pageInfo: {hasNextPage: false, endCursor: null}}}}')"
lin_reset
lin_data 'issueCreate' '{"issueCreate":{"success":true,"issue":{"id":"uuid-issue-12","number":12,"team":{"key":"ENG"}}}}'
lin_data 'teams(filter:' "$TEAM_NODE"
lin_seed_issue 12 started
lin_data 'children(' "$CHILDREN_P1"
lin_data 'children(' "$CHILDREN_P2"
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "same-titled child on page 2 → exit 0" "0" "$rc"
assert_no_create "and no issue is created for a sibling on a later page"
assert_eq "stdout is the page-2 child" "linear:acme/ENG#44" "$(jq -r '.id' <<<"$(lin_out)")"
assert_contains "the second page was requested with the cursor" "$(lin_bodies)" '"after":"c1"'

# Without --parent nothing is read and the item is created as before.
seed_create "[$(child_node 40 started child)]"
rc="$(lin_run "$S" --title "child")"
assert_eq "same title without --parent → exit 0" "0" "$rc"
assert_contains "creates the item" "$(lin_requests)" "issueCreate"
assert_eq "returning the new item, not a sibling" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"
if [[ "$(lin_requests)" == *"children("* ]]; then
  fail "and reads no children" "no children query" "children query issued"
else
  pass "and reads no children"
fi

# A failed children read exits non-zero rather than creating a possible duplicate.
lin_reset
lin_data 'issueCreate' '{"issueCreate":{"success":true,"issue":{"id":"uuid-issue-12","number":12,"team":{"key":"ENG"}}}}'
lin_data 'teams(filter:' "$TEAM_NODE"
lin_seed_issue 12 started
lin_seed 'children(' 200 '{"errors":[{"message":"forbidden","extensions":{"type":"Forbidden"}}]}'
rc="$(lin_run "$S" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "refused children read → exit 4" "4" "$rc"
assert_no_create "and nothing is created when the children read fails"

# The children walk is bounded by the declared ceiling: a truncated child list would read
# as "no duplicate", so an endless feed stops with an error and creates nothing. A fixture
# copy of the adapter declares a ceiling of 2; the last route repeats, so one page is endless.
FIX_ADAPTER="$LIN_FIX/adapter"
mkdir -p "$FIX_ADAPTER"
cp "$D"/*.sh "$FIX_ADAPTER/"
jq '.limits.list_items_max = 2' "$D/capabilities.json" >"$FIX_ADAPTER/capabilities.json"
lin_reset
lin_data 'issueCreate' '{"issueCreate":{"success":true,"issue":{"id":"uuid-issue-12","number":12,"team":{"key":"ENG"}}}}'
lin_data 'teams(filter:' "$TEAM_NODE"
lin_seed_issue 12 started
lin_data 'children(' "$(jq -cn --argjson n "[$(child_node 40 started 'other work')]" \
  '{issue: {children: {nodes: $n, pageInfo: {hasNextPage: true, endCursor: "always-more"}}}}')"
rc="$(WIT_SEAM_LIB_DIR="$D/../../lib" lin_run "$FIX_ADAPTER/create-item.sh" --title "child" --parent "linear:acme/ENG#12")"
assert_eq "an endless children feed stops → exit 1" "1" "$rc"
assert_no_create "and nothing is created past the ceiling"
assert_contains "stderr names the parent and the ceiling" "$(lin_err)" "children of linear:acme/ENG#12 passed the declared ceiling of 2"
assert_eq "the walk stopped one page past the ceiling" "3" "$(grep -c 'children(' <<<"$(lin_requests)")"

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
# team's issues.
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

# --- the label walk is BOUNDED, and says which kind of "not found" it means ---
# A null cursor stops the walk (above); a server that keeps supplying VALID ones does not,
# and without a ceiling create-item would hang with ALL_LABELS growing. Routes sharing a
# pattern are call-ordered and the last one repeats, so a single always-more page is exactly
# the misbehaving server this bound exists for: 50 labels per page against a ceiling of 1000
# means the walk stops on page 21 rather than never.
lin_reset
lin_data 'teams(filter:' "$TEAM_NODE"
ENDLESS_PAGE="$(jq -cn '{issueLabels: {nodes: ([range(50)] | map({id: "uuid-\(.)", name: "filler: \(.)"})), pageInfo: {hasNextPage: true, endCursor: "always-more"}}}')"
lin_data 'issueLabels(' "$ENDLESS_PAGE"
rc="$(lin_run "$S" --title "x" --labels "never: present")"
assert_eq "an endless label feed terminates → exit 5" "5" "$rc"
# The message must distinguish truncated-so-it-might-exist from absent-so-create-it. A bare
# "create them first" against a truncated list sends someone to create a label that is
# already there — the same wrong-direction failure the org-label fix removes for gitea.
assert_contains "and says the list was truncated, not that the label is absent" \
  "$(lin_err)" "truncated at the declared ceiling"
if [[ "$(lin_err)" == *"create them first"* ]]; then
  fail "and does not tell the operator to create it" "no create-them-first" "create-them-first shown"
else
  pass "and does not tell the operator to create it"
fi
# 1000/50 = 20 full pages, and the 21st is what pushes LABEL_SEEN past the ceiling.
assert_eq "the walk stopped at the ceiling rather than running on" "21" \
  "$(grep -c 'issueLabels(' <<<"$(lin_bodies)")"

[[ $FAILED -eq 0 ]] || exit 1
