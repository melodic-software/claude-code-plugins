#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# claim: offline contract tests for the lease protocol's acquisition half.
#
# The cases that matter are the refusals. A claim that wrongly SUCCEEDS hands two
# sessions the same item and neither finds out; a claim that wrongly fails only costs a
# retry. So every case here that asserts exit 7 is asserting the expensive direction.
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claim.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LONG_AGO="1999-01-01T00:00:00Z"

# --- offline usage errors (no network) ---
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "not-an-id"
assert_usage_error "$S" "github:o/r#1"
assert_usage_error "$S" "linear:acme/ENG#12" --ttl-hours
assert_usage_error "$S" "linear:acme/ENG#12" --ttl-hours "-1"
assert_usage_error "$S" "linear:acme/ENG#12" --ttl-hours "soon"

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

# seed_claim_ok <existing-comments-json> — the operations a successful claim performs,
# with a caller-chosen set of pre-existing comments. Seeded most-specific-first, since
# the mock matches on the first pattern the GraphQL document contains.
seed_claim_ok() {
  lin_reset
  lin_data 'viewer' '{"viewer":{"id":"uuid-user-kyle","displayName":"kyle","email":"kyle@example.invalid"}}'
  lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
  lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-mine","createdAt":"2026-08-20T12:00:00.500Z"}}}'
  lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
  lin_data 'comments(' "$(jq -cn --argjson n "$1" '{issue: {comments: {nodes: $n, pageInfo: {hasNextPage: false}}}}')"
  lin_seed_issue 12 started
}

# --- happy path: no existing lease ---
seed_claim_ok '[]'
rc="$(lin_run "$S" "linear:acme/ENG#12" --session-id "sess-1")"
assert_eq "claim on an unclaimed item → exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_eq "id" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"
# The holder is the AUTHENTICATED user, never a caller-supplied name — a claim must not
# be attributable to someone who did not make it.
assert_eq "holder is the authenticated viewer" "kyle" "$(jq -r '.holder' <<<"$(lin_out)")"
assert_eq "session_id is carried through" "sess-1" "$(jq -r '.session_id' <<<"$(lin_out)")"
assert_eq "ttl_hours defaults from the binding" "24" "$(jq -r '.ttl_hours' <<<"$(lin_out)")"
# The handle is minted from the comment's createdAt: 2026-08-20T12:00:00.500Z.
# Numeric and ordered by construction, which is what same-handle arbitration needs.
assert_eq "lease_comment_id is a numeric handle" "true" \
  "$(jq -r '.lease_comment_id | type == "number"' <<<"$(lin_out)")"
assert_contains "the lease marker was posted" "$(lin_bodies)" "work-item-lease v1"
assert_contains "the assignee was set" "$(lin_requests)" "issueUpdate"

# --- a live FOREIGN lease is refused before anything is written ---
LIVE_FOREIGN="$(jq -cn --arg b "$(lin_lease_body 1000 "someone-else" "$NOW" 24)" \
  '[{id: "uuid-comment-theirs", body: $b, createdAt: "2026-08-20T11:00:00.000Z"}]')"
seed_claim_ok "$LIVE_FOREIGN"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "live foreign lease → exit 7" "7" "$rc"
assert_contains "and names the holder" "$(lin_err)" "someone-else"
# Nothing was written: no assignment, no comment. Checking first is what keeps a
# doomed claim from touching the item at all.
if [[ "$(lin_requests)" == *"issueUpdate"* ]]; then
  fail "a refused claim writes nothing" "no issueUpdate" "issueUpdate issued"
else
  pass "a refused claim writes nothing"
fi

# --- an EXPIRED lease does not block a new claim ---
EXPIRED="$(jq -cn --arg b "$(lin_lease_body 1000 "someone-else" "$LONG_AGO" 24)" \
  '[{id: "uuid-comment-old", body: $b, createdAt: "1999-01-01T00:00:00.000Z"}]')"
seed_claim_ok "$EXPIRED"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "expired foreign lease does not block" "0" "$rc"

# --- a SUPERSEDED lease does not block, even within its TTL ---
SUPERSEDED="$(jq -cn --arg b "$(lin_lease_body 1000 "someone-else" "$NOW" 24 "$NOW")" \
  '[{id: "uuid-comment-sup", body: $b, createdAt: "2026-08-20T11:00:00.000Z"}]')"
seed_claim_ok "$SUPERSEDED"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "superseded lease does not block" "0" "$rc"

# --- a ttl-0 lease is born expired and never counts as live ---
TTL_ZERO="$(jq -cn --arg b "$(lin_lease_body 1000 "someone-else" "$NOW" 0)" \
  '[{id: "uuid-comment-zero", body: $b, createdAt: "2026-08-20T11:00:00.000Z"}]')"
seed_claim_ok "$TTL_ZERO"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "ttl-0 lease is not live" "0" "$rc"

# --- the race that only step 4 can catch ---
#
# This is the case Linear's SINGLE assignee field makes invisible: the rival assigned
# itself, we overwrote it, and re-reading the assignee shows only us. The rival's lease
# comment lands between our pre-check and our arbitration re-read — so the pre-check
# sees an unclaimed item and only the re-read reveals the collision.
#
# Modelled by seeding the comments query TWICE: empty first, then both leases. A single
# static response could not express it, and a "race" test written against one is really
# testing the pre-check a second time.
#
# Our comment is createdAt 12:00:00.500. Handles are epoch milliseconds, so the rival's
# one-second-earlier comment has a strictly lower handle and wins.
# portability-ok: GNU-first rung of a dual-dialect ladder; the BSD `-j -f` spelling is the `||` fallback
MINE_S="$(date -u -d '2026-08-20T12:00:00Z' +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-08-20T12:00:00Z' +%s)"
MINE_HANDLE="$((MINE_S * 1000 + 500))"

seed_race() {
  lin_reset
  lin_data 'viewer' '{"viewer":{"id":"uuid-user-kyle","displayName":"kyle","email":"kyle@example.invalid"}}'
  lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
  lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-mine","createdAt":"2026-08-20T12:00:00.500Z"}}}'
  lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
  # Pre-check sees nothing; the re-read sees ours plus the rival's.
  lin_comments '[]' "$1"
  lin_seed_issue 12 started
}

MINE_NODE="$(jq -cn --arg b "$(lin_lease_body "$MINE_HANDLE" "kyle" "$NOW" 24)" \
  '{id: "uuid-comment-mine", body: $b, createdAt: "2026-08-20T12:00:00.500Z"}')"

seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$((MINE_HANDLE - 1500))" "rival" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-rival", body: $theirs, createdAt: "2026-08-20T11:59:59.000Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "an earlier live lease wins the race → exit 7" "7" "$rc"
assert_contains "and the rival is named" "$(lin_err)" "rival"
# Losing means superseding our OWN marker, never touching the rival's.
assert_contains "our own lease is superseded on back-off" "$(lin_bodies)" "superseded_at"

# --- a LATER live lease does not beat ours ---
seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$((MINE_HANDLE + 5000))" "latecomer" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-late", body: $theirs, createdAt: "2026-08-20T12:00:05.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a later live lease does not beat ours" "0" "$rc"

# --- same-millisecond tie breaks on the comment id, deterministically ---
# Handles are millisecond timestamps, so a tie is possible. Without a tiebreak both
# racers would read themselves as earliest and both would claim.
seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$MINE_HANDLE" "tie-rival" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-aaa", body: $theirs, createdAt: "2026-08-20T12:00:00.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
# "uuid-comment-aaa" sorts before "uuid-comment-mine", so the rival wins the tie.
assert_eq "same-handle tie is broken on comment id → exit 7" "7" "$rc"
assert_contains "the tie winner is named" "$(lin_err)" "tie-rival"

# And the tie is decided the same way from BOTH sides: with our comment id sorting
# first, we win the identical situation. A tiebreak that is not symmetric is not a
# tiebreak — it just moves the double-claim to a different pair of ids.
seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$MINE_HANDLE" "tie-loser" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-zzz", body: $theirs, createdAt: "2026-08-20T12:00:00.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "the same tie decided from the other side → exit 0" "0" "$rc"

# --- a live foreign lease with a MALFORMED handle is still refused ---
# `lease_comment_id` is consumer-writable in practice: hand-edited markers, or another
# tool writing the same v1 shape. A non-numeric one used to make the reader's `--argjson`
# fail, which emptied the accumulator and — because jq over empty input prints nothing
# and EXITS 0 — returned success-with-no-output. Callers read that as "nothing is
# claimed" and handed out a second lease over a live one. The `|| exit "$?"` guard at
# the call site cannot catch it, because the failure never arrives as a non-zero status.
# Built directly rather than via lin_lease_body, which types the handle as a number —
# a STRING handle is precisely the shape under test.
MALFORMED_MARKER="$(jq -cn --arg t "$NOW" \
  '{schema_version: "1.0", holder: "someone-else", acquired_at: $t, renewed_at: $t,
    ttl_hours: 24, ttl_minutes: 0, lease_comment_id: "abc"}')"
MALFORMED="$(jq -cn --arg b "<!-- work-item-lease v1 $MALFORMED_MARKER -->" \
  '[{id: "uuid-comment-theirs", body: $b, createdAt: "2026-08-20T11:00:00.000Z"}]')"
seed_claim_ok "$MALFORMED"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a malformed lease handle does not hide a live foreign lease" "7" "$rc"
assert_contains "…and still names the holder" "$(lin_err)" "someone-else"
if [[ "$(lin_requests)" == *"issueUpdate"* ]]; then
  fail "a claim refused on a malformed handle writes nothing" "no issueUpdate" "issueUpdate issued"
else
  pass "a claim refused on a malformed handle writes nothing"
fi

# --- the partial-claim window: assigned, then the lease write fails ---
# The assignment lands first and the lease is posted second, so a failure in between
# leaves the issue ASSIGNED WITH NO LEASE. That state is unrecoverable through the
# seam — list-frontier excludes assigned items and reclaim refuses an item with no
# active lease — so a transient API failure would park the item indefinitely. The
# rollback trap is what prevents it; without the trap this asserts 0 rollbacks.
# Seeded by hand rather than via seed_claim_ok: the mock matches the FIRST seeded
# route whose pattern the query contains, so a failing commentCreate has to be seeded
# before the success route, not after it.
lin_reset
lin_data 'viewer' '{"viewer":{"id":"uuid-user-kyle","displayName":"kyle","email":"kyle@example.invalid"}}'
lin_seed 'commentCreate' 200 '{"errors":[{"message":"upstream exploded"}]}'
lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
lin_data 'comments(' '{"issue":{"comments":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}'
lin_seed_issue 12 started
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a failed lease write reports the failure" "1" "$rc"
assert_eq "…and the assignment is rolled back, leaving no assigned-with-no-lease item" \
  "1" "$(lin_bodies | grep -c '"assigneeId":null')"

# The rollback must not fire blind. The trap stays armed across the update-comment
# write and the arbitration read, both of which exit on failure — so a concurrent
# session can legitimately win the claim inside that window, posting its own lease and
# overwriting Linear's SINGLE assignee field. Clearing unconditionally on our way out
# would strip that live claim: the same defect reclaim.sh was fixed for, reintroduced
# from the rollback path.
lin_reset
lin_data 'viewer' '{"viewer":{"id":"uuid-user-kyle","displayName":"kyle","email":"kyle@example.invalid"}}'
lin_seed 'commentUpdate' 200 '{"errors":[{"message":"rate limited"}]}'
lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-mine","createdAt":"2026-08-20T12:00:00.500Z"}}}'
lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
lin_data 'comments(' '{"issue":{"comments":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}'
# The issue re-read the rollback performs reports a DIFFERENT assignee — the concurrent
# winner — so the compare must decline to clear it.
lin_data 'issues(filter:' "$(jq -cn --argjson i \
  "$(jq -c '.assignee = {displayName: "other-session", email: "other@example.invalid"}' <<<"$(lin_issue_json 12 started)")" \
  '{issues: {nodes: [$i]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a failure after the lease post still reports the failure" "1" "$rc"
assert_eq "…and the rollback leaves a concurrent winner's assignment alone" \
  "0" "$(lin_bodies | grep -c '"assigneeId":null')"

# Losing to a rival who holds a LIVE lease must not clear the assignee at all. The
# winner is working the item, and `lib/frontier.sh` selects purely on assignee emptiness
# with no lease check — so clearing here would put actively-worked work back on the
# frontier. A stale name in the slot is cosmetic; an empty slot is a double-work
# invitation. This also has to hold when the rival shares our login, which a display-name
# compare cannot detect: HOLDER is the authenticated user's display name, not a session
# identity, and same-login racing is the ordinary case the handle arbitration exists for.
seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$((MINE_HANDLE - 1000))" "earlier-rival" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-aaa", body: $theirs, createdAt: "2026-08-20T11:59:59.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "losing the race still exits 7" "7" "$rc"
assert_eq "…leaving the live winner's assignment untouched" \
  "0" "$(lin_bodies | grep -c '"assigneeId":null')"

# The same race, with the rival sharing OUR login. A display-name compare cannot tell
# this from our own write, so under the old guard the loser cleared the winner's live
# assignment. The live-lease test is identity-independent and holds here too.
seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$((MINE_HANDLE - 1000))" "kyle" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-aaa", body: $theirs, createdAt: "2026-08-20T11:59:59.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a same-login rival still wins the race" "7" "$rc"
assert_eq "…and their live assignment is not stripped by the loser" \
  "0" "$(lin_bodies | grep -c '"assigneeId":null')"

# --- scope boundary ---
lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#5")"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_eq "and nothing was requested" "" "$(lin_requests)"

[[ $FAILED -eq 0 ]] || exit 1
