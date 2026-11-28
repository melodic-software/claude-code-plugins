#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claim.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LONG_AGO="1999-01-01T00:00:00Z"

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

seed_claim_ok() {
  lin_reset
  lin_data 'viewer' '{"viewer":{"id":"uuid-user-kyle","displayName":"kyle","email":"kyle@example.invalid"}}'
  lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
  lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-mine","createdAt":"2026-08-20T12:00:00.500Z"}}}'
  lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
  lin_data 'comments(' "$(jq -cn --argjson n "$1" '{issue: {comments: {nodes: $n, pageInfo: {hasNextPage: false}}}}')"
  lin_seed_issue 12 started
}

seed_claim_ok '[]'
rc="$(lin_run "$S" "linear:acme/ENG#12" --session-id "sess-1")"
assert_eq "claim on an unclaimed item → exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_eq "id" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"
assert_eq "holder is the authenticated viewer" "kyle" "$(jq -r '.holder' <<<"$(lin_out)")"
assert_eq "session_id is carried through" "sess-1" "$(jq -r '.session_id' <<<"$(lin_out)")"
assert_eq "ttl_hours defaults from the binding" "24" "$(jq -r '.ttl_hours' <<<"$(lin_out)")"
assert_eq "lease_comment_id is a numeric handle" "true" \
  "$(jq -r '.lease_comment_id | type == "number"' <<<"$(lin_out)")"
assert_contains "the lease marker was posted" "$(lin_bodies)" "work-item-lease v1"
assert_contains "the assignee was set" "$(lin_requests)" "issueUpdate"

LIVE_FOREIGN="$(jq -cn --arg b "$(lin_lease_body 1000 "someone-else" "$NOW" 24)" \
  '[{id: "uuid-comment-theirs", body: $b, createdAt: "2026-08-20T11:00:00.000Z"}]')"
seed_claim_ok "$LIVE_FOREIGN"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "live foreign lease → exit 7" "7" "$rc"
assert_contains "and names the holder" "$(lin_err)" "someone-else"
if [[ "$(lin_requests)" == *"issueUpdate"* ]]; then
  fail "a refused claim writes nothing" "no issueUpdate" "issueUpdate issued"
else
  pass "a refused claim writes nothing"
fi

EXPIRED="$(jq -cn --arg b "$(lin_lease_body 1000 "someone-else" "$LONG_AGO" 24)" \
  '[{id: "uuid-comment-old", body: $b, createdAt: "1999-01-01T00:00:00.000Z"}]')"
seed_claim_ok "$EXPIRED"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "expired foreign lease does not block" "0" "$rc"

SUPERSEDED="$(jq -cn --arg b "$(lin_lease_body 1000 "someone-else" "$NOW" 24 "$NOW")" \
  '[{id: "uuid-comment-sup", body: $b, createdAt: "2026-08-20T11:00:00.000Z"}]')"
seed_claim_ok "$SUPERSEDED"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "superseded lease does not block" "0" "$rc"

TTL_ZERO="$(jq -cn --arg b "$(lin_lease_body 1000 "someone-else" "$NOW" 0)" \
  '[{id: "uuid-comment-zero", body: $b, createdAt: "2026-08-20T11:00:00.000Z"}]')"
seed_claim_ok "$TTL_ZERO"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "ttl-0 lease is not live" "0" "$rc"

# portability-ok: GNU-first rung of a dual-dialect ladder; the BSD `-j -f` spelling is the `||` fallback
MINE_S="$(date -u -d '2026-08-20T12:00:00Z' +%s 2>/dev/null || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' '2026-08-20T12:00:00Z' +%s)"
MINE_HANDLE="$((MINE_S * 1000 + 500))"

seed_race() {
  lin_reset
  lin_data 'viewer' '{"viewer":{"id":"uuid-user-kyle","displayName":"kyle","email":"kyle@example.invalid"}}'
  lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
  lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-mine","createdAt":"2026-08-20T12:00:00.500Z"}}}'
  lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
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
assert_contains "our own lease is superseded on back-off" "$(lin_bodies)" "superseded_at"

seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$((MINE_HANDLE + 5000))" "latecomer" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-late", body: $theirs, createdAt: "2026-08-20T12:00:05.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a later live lease does not beat ours" "0" "$rc"

seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$MINE_HANDLE" "tie-rival" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-aaa", body: $theirs, createdAt: "2026-08-20T12:00:00.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "same-handle tie is broken on comment id → exit 7" "7" "$rc"
assert_contains "the tie winner is named" "$(lin_err)" "tie-rival"

seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$MINE_HANDLE" "tie-loser" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-zzz", body: $theirs, createdAt: "2026-08-20T12:00:00.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "the same tie decided from the other side → exit 0" "0" "$rc"

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

lin_reset
lin_data 'viewer' '{"viewer":{"id":"uuid-user-kyle","displayName":"kyle","email":"kyle@example.invalid"}}'
lin_seed 'commentUpdate' 200 '{"errors":[{"message":"rate limited"}]}'
lin_data 'commentCreate' '{"commentCreate":{"success":true,"comment":{"id":"uuid-comment-mine","createdAt":"2026-08-20T12:00:00.500Z"}}}'
lin_data 'issueUpdate' '{"issueUpdate":{"success":true}}'
lin_data 'comments(' '{"issue":{"comments":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}'
lin_data 'issues(filter:' "$(jq -cn --argjson i \
  "$(jq -c '.assignee = {displayName: "other-session", email: "other@example.invalid"}' <<<"$(lin_issue_json 12 started)")" \
  '{issues: {nodes: [$i]}}')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a failure after the lease post still reports the failure" "1" "$rc"
assert_eq "…and the rollback leaves a concurrent winner's assignment alone" \
  "0" "$(lin_bodies | grep -c '"assigneeId":null')"

seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$((MINE_HANDLE - 1000))" "earlier-rival" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-aaa", body: $theirs, createdAt: "2026-08-20T11:59:59.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "losing the race still exits 7" "7" "$rc"
assert_eq "…leaving the live winner's assignment untouched" \
  "0" "$(lin_bodies | grep -c '"assigneeId":null')"

seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$((MINE_HANDLE - 1000))" "kyle" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-aaa", body: $theirs, createdAt: "2026-08-20T11:59:59.500Z"}]')"
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "a same-login rival still wins the race" "7" "$rc"
assert_eq "…and their live assignment is not stripped by the loser" \
  "0" "$(lin_bodies | grep -c '"assigneeId":null')"

seed_race "$(jq -cn --argjson mine "$MINE_NODE" \
  --arg theirs "$(lin_lease_body "$((MINE_HANDLE - 1000))" "earlier-rival" "$NOW" 24)" \
  '[$mine, {id: "uuid-comment-aaa", body: $theirs, createdAt: "2026-08-20T11:59:59.500Z"}]')"
lin_seed 'comments(' 500 '{"errors":[{"message":"upstream exploded"}]}'
rc="$(lin_run "$S" "linear:acme/ENG#12")"
assert_eq "…and an unreadable lease set never clears the assignee" \
  "0" "$(lin_bodies | grep -c '"assigneeId":null')"

lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#5")"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_eq "and nothing was requested" "" "$(lin_requests)"

[[ $FAILED -eq 0 ]] || exit 1
