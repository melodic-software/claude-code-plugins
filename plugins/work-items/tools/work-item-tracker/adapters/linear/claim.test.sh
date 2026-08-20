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

# --- scope boundary ---
lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#5")"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_eq "and nothing was requested" "" "$(lin_requests)"

[[ $FAILED -eq 0 ]] || exit 1
