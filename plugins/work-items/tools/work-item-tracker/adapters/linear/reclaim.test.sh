#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# reclaim: offline contract tests.
#
# Every case here guards the same invariant: a LIVE lease is never the intended target.
# Reclaiming one strips a working session's claim and hands the item to someone else
# while the first is still editing — the most expensive failure this adapter can have,
# and the one no error message would surface at the time.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/reclaim.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LONG_AGO="1999-01-01T00:00:00Z"
# portability-ok: GNU-first rung of a ladder whose fallback echoes the same literal — the GNU
# form round-trips its own input here, so the BSD path needs no `date` call at all
RECENT="$(date -u -d '1999-06-01T00:00:00Z' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '1999-06-01T00:00:00Z')"
HANDLE=1787227200500

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "not-an-id"
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "linear:acme/ENG#12" extra

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

lease_node() {
  jq -cn --arg b "$(lin_lease_body "$1" "${2:-kyle}" "$3" "${4:-24}" "${5:-}")" \
    '[{id: "uuid-comment-mine", body: $b, createdAt: "2026-08-20T12:00:00.500Z"}]'
}

# seed_reclaim <lease-nodes> <activity-nodes> [assignee-display-name]
# The comments query answers three times over a full reclaim: the initial read, the
# activity check, and the revalidation. Seeding the same set for all three models the
# common no-concurrency case.
seed_reclaim() {
  local nodes="$1" activity="$2" assignee="${3:-kyle}"
  lin_reset
  lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
  lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-note","createdAt":"2026-08-20T13:00:00.000Z"}}}'
  lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
  # The activity query selects `comments(first: 50)` with no `after`, so it matches the
  # same pattern; it is the SECOND call, which is why the sequence has three entries.
  lin_comments "$nodes" "$activity" "$nodes"
  lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" --arg a "$assignee" \
    '{issues: {nodes: [($i | .assignee = (if ($a | length) > 0 then {displayName: $a, email: "x@example.invalid"} else null end))]}}')"
}

# --- a LIVE lease is left alone ---
seed_reclaim "$(lease_node "$HANDLE" kyle "$NOW" 24)" '[]'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "live lease → exit 0" "0" "$rc"
assert_eq "reclaimed is false" "false" "$(jq -r '.reclaimed' <<<"$(lin_out)")"
assert_contains "and the reason says so" "$(jq -r '.reason' <<<"$(lin_out)")" "still live"
if [[ "$(lin_requests)" == *"issueUpdate"* ]]; then
  fail "a live lease is never written to" "no issueUpdate" "issueUpdate issued"
else
  pass "a live lease is never written to"
fi

# --- no lease at all is a clean no-op ---
seed_reclaim '[]' '[]'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "no lease → exit 0" "0" "$rc"
assert_eq "reclaimed is false" "false" "$(jq -r '.reclaimed' <<<"$(lin_out)")"
assert_contains "reason names the absence" "$(jq -r '.reason' <<<"$(lin_out)")" "no active lease"

# --- an expired lease with NO activity is reclaimed ---
seed_reclaim "$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)" '[]'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "expired, quiet lease → exit 0" "0" "$rc"
assert_eq "reclaimed is true" "true" "$(jq -r '.reclaimed' <<<"$(lin_out)")"
assert_contains "the lease is superseded" "$(lin_bodies)" "superseded_at"
assert_contains "the holder is unassigned" "$(lin_requests)" "issueUpdate"
assert_contains "an explanatory comment is posted" "$(lin_bodies)" "Reclaimed:"

# --- an expired lease WITH activity is renewed, not reclaimed ---
# The holder is demonstrably still working; taking the item would interrupt them.
ACTIVITY="$(jq -cn --arg t "$RECENT" '[{body: "still working on this", createdAt: $t}]')"
seed_reclaim "$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)" "$ACTIVITY"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "expired lease with activity → exit 0" "0" "$rc"
assert_eq "reclaimed is false" "false" "$(jq -r '.reclaimed' <<<"$(lin_out)")"
assert_contains "reason names the activity" "$(jq -r '.reason' <<<"$(lin_out)")" "activity"
if [[ "$(lin_requests)" == *"issueUpdate"* ]]; then
  fail "an active holder is not unassigned" "no issueUpdate" "issueUpdate issued"
else
  pass "an active holder is not unassigned"
fi

# A LEASE comment does not count as activity. If it did, every renewal would count as
# activity and the lease would never expire — the item would be held forever.
LEASE_ONLY_ACTIVITY="$(jq -cn --arg b "$(lin_lease_body "$HANDLE" kyle "$RECENT" 24)" --arg t "$RECENT" \
  '[{body: $b, createdAt: $t}]')"
seed_reclaim "$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)" "$LEASE_ONLY_ACTIVITY"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a lease comment is not activity → reclaimed" "true" "$(jq -r '.reclaimed' <<<"$(lin_out)")"

# A comment OLDER than renewed_at is not activity either — it predates the lease.
OLD_ACTIVITY="$(jq -cn '[{body: "from before the claim", createdAt: "1998-01-01T00:00:00Z"}]')"
seed_reclaim "$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)" "$OLD_ACTIVITY"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a pre-lease comment is not activity → reclaimed" "true" "$(jq -r '.reclaimed' <<<"$(lin_out)")"

# --- a co-assignee is NOT stripped ---
# Someone else in the assignee slot took the item after this lease expired. Clearing it
# would strip a LIVE claim and hand the item back to the frontier while they work it.
seed_reclaim "$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)" '[]' "someone-else"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "expired lease, different assignee → exit 0" "0" "$rc"
assert_eq "still reclaimed (the lease is released)" "true" "$(jq -r '.reclaimed' <<<"$(lin_out)")"
# The lease is superseded, but the OTHER person's assignment is left alone.
UNASSIGNED="$(lin_bodies | jq -rs '[.[] | select(.query | test("issueUpdate")) | .variables.input.assigneeId] | length' 2>/dev/null || echo 0)"
assert_eq "the other assignee is left in place" "0" "$UNASSIGNED"

# --- the revalidation window ---
# The activity read round-trips, so a concurrent claimer can renew or supersede in
# between. Revalidation before the mutation narrows that window: here the lease comes
# back LIVE on the third read, and reclaim declines.
seed_reclaim "$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)" '[]'
lin_reset
lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
lin_comments \
  "$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)" \
  '[]' \
  "$(lease_node "$HANDLE" kyle "$NOW" 24)"
lin_seed_issue 12 started
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a lease renewed under us → exit 0" "0" "$rc"
assert_eq "and is NOT reclaimed" "false" "$(jq -r '.reclaimed' <<<"$(lin_out)")"
assert_contains "reason names the change" "$(jq -r '.reason' <<<"$(lin_out)")" "changed"

# A concurrent claimer does NOT renew this lease — it posts its own, under a different
# handle, and wins its own arbitration without ever touching this expired one. So the
# handle-keyed re-read above still finds our lease present, un-superseded and expired,
# and every check on it passes. Only looking for a live lease we do not hold catches it.
# Left uncaught, reclaim supersedes and then unassigns the rival mid-work.
RIVAL_HANDLE=1787227200999
lin_reset
lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-note","createdAt":"2026-08-20T13:00:00.000Z"}}}'
lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
MINE_EXPIRED="$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)"
RIVAL_LIVE="$(jq -cn --arg b "$(lin_lease_body "$RIVAL_HANDLE" rival "$NOW" 24)" \
  '[{id: "uuid-comment-rival", body: $b, createdAt: "2026-08-20T12:30:00.000Z"}]')"
BOTH="$(jq -cn --argjson a "$MINE_EXPIRED" --argjson b "$RIVAL_LIVE" '$a + $b')"
lin_comments "$MINE_EXPIRED" '[]' "$BOTH"
# The re-fetched issue shows the rival holding the assignment, not the original holder.
lin_data 'issues(filter:' "$(jq -cn --argjson i "$(lin_issue_json 12 started)" \
  '{issues: {nodes: [($i | .assignee = {displayName: "rival", email: "r@example.invalid"})]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a rival lease taken during the window → exit 0" "0" "$rc"
assert_eq "and the item is NOT reclaimed" "false" "$(jq -r '.reclaimed' <<<"$(lin_out)")"
UNASSIGNED="$(lin_bodies | jq -rs '[.[] | select(.query | test("issueUpdate"))] | length' 2>/dev/null || echo 0)"
assert_eq "and the rival's assignment is untouched" "0" "$UNASSIGNED"

# Activity on a LATER page must still count. Linear returns comments oldest-first, so on
# a long-running item the comments that prove the holder is alive are the ones a
# first-page-only read never sees — and reclaiming then releases a live lease.
lin_reset
lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-note","createdAt":"2026-08-20T13:00:00.000Z"}}}'
lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
EXPIRED="$(lease_node "$HANDLE" kyle "$LONG_AGO" 24)"
RECENT_TALK="$(jq -cn --arg t "$NOW" '[{id: "uuid-c-late", body: "still on this", createdAt: $t}]')"
# 1: initial lease read. 2-3: the activity check, whose recent comment is on page TWO.
# 4: the revalidation read.
lin_comments_page "$EXPIRED" false
lin_comments_page '[]' true "cursor-1"
lin_comments_page "$RECENT_TALK" false
lin_comments_page "$EXPIRED" false
lin_seed_issue 12 started
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "activity on a later page → exit 0" "0" "$rc"
assert_eq "and the item is NOT reclaimed" "false" "$(jq -r '.reclaimed' <<<"$(lin_out)")"
assert_contains "reason names the activity" "$(jq -r '.reason' <<<"$(lin_out)")" "activity"

# --- scope boundary ---
lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#5")"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_eq "and nothing was requested" "" "$(lin_requests)"

[[ $FAILED -eq 0 ]] || exit 1
