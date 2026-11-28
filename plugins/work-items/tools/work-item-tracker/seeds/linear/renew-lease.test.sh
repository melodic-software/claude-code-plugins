#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/renew-lease.sh"
D="$(dirname "$S")"
source "$D/../../lib/verb-test-helpers.sh"
# shellcheck source=mock.sh
source "$D/mock.sh"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LONG_AGO="1999-01-01T00:00:00Z"
HANDLE=1787227200500

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S"
assert_usage_error "$S" "linear:acme/ENG#12"
assert_usage_error "$S" "linear:acme/ENG#12" --lease-comment-id
assert_usage_error "$S" "linear:acme/ENG#12" --lease-comment-id "abc"
assert_usage_error "$S" "not-an-id" --lease-comment-id "$HANDLE"
assert_usage_error "$S" "github:o/r#1" --lease-comment-id "$HANDLE"

lin_fixture_init
trap 'rm -rf "$LIN_FIX"' EXIT

seed_lease() {
  lin_reset
  lin_data 'commentUpdate' '{"commentUpdate":{"success":true}}'
  lin_comments "$1"
  lin_seed_issue 12 started
}

seed_lease "$(lin_lease_node "$HANDLE" kyle "$NOW" 24)"
rc="$(lin_run "$S" "linear:acme/ENG#12" --lease-comment-id "$HANDLE")"
assert_eq "renewing a live lease → exit 0" "0" "$rc"
assert_eq "schema_version" "1.0" "$(jq -r '.schema_version' <<<"$(lin_out)")"
assert_eq "id" "linear:acme/ENG#12" "$(jq -r '.id' <<<"$(lin_out)")"
assert_eq "holder is unchanged" "kyle" "$(jq -r '.holder' <<<"$(lin_out)")"
assert_eq "the handle is unchanged" "$HANDLE" "$(jq -r '.lease_comment_id' <<<"$(lin_out)")"
assert_eq "acquired_at is preserved" "$NOW" "$(jq -r '.acquired_at' <<<"$(lin_out)")"
assert_contains "the existing comment is updated" "$(lin_requests)" "commentUpdate"
if [[ "$(lin_requests)" == *"commentCreate"* ]]; then
  fail "renew posts no new comment" "no commentCreate" "commentCreate issued"
else
  pass "renew posts no new comment"
fi

seed_lease "$(lin_lease_node "$HANDLE" kyle "$LONG_AGO" 24)"
rc="$(lin_run "$S" "linear:acme/ENG#12" --lease-comment-id "$HANDLE")"
assert_eq "expired lease → exit 7" "7" "$rc"
assert_contains "and says why reviving it is wrong" "$(lin_err)" "TTL handoff"
if [[ "$(lin_requests)" == *"commentUpdate"* ]]; then
  fail "an expired lease is not written to" "no commentUpdate" "commentUpdate issued"
else
  pass "an expired lease is not written to"
fi

seed_lease "$(lin_lease_node "$HANDLE" kyle "$NOW" 24 "$NOW")"
rc="$(lin_run "$S" "linear:acme/ENG#12" --lease-comment-id "$HANDLE")"
assert_eq "superseded lease → exit 7" "7" "$rc"
assert_contains "and says it was superseded" "$(lin_err)" "superseded"

EARLIER="$(jq -cn --arg b "$(lin_lease_body $((HANDLE - 1000)) kyle "$NOW" 24)" \
  '[{id: "uuid-comment-earlier", body: $b, createdAt: "2026-08-20T12:00:00.500Z"}]')"
seed_lease "$(jq -cn --argjson a "$EARLIER" --argjson b "$(lin_lease_node "$HANDLE" kyle "$NOW" 24)" '$a + $b')"
rc="$(lin_run "$S" "linear:acme/ENG#12" --lease-comment-id "$HANDLE")"
assert_eq "an outranked live lease → exit 7" "7" "$rc"
assert_contains "and names the earlier lease" "$(lin_err)" "outranked"
if [[ "$(lin_requests)" == *"commentUpdate"* ]]; then
  fail "an outranked lease is not written to" "no commentUpdate" "commentUpdate issued"
else
  pass "an outranked lease is not written to"
fi
rc="$(lin_run "$S" "linear:acme/ENG#12" --lease-comment-id "$((HANDLE - 1000))")"
assert_eq "the earlier lease renews (0) under a newer live lease" "0" "$rc"

seed_lease "$(lin_lease_node "$HANDLE" kyle "$NOW" 0)"
rc="$(lin_run "$S" "linear:acme/ENG#12" --lease-comment-id "$HANDLE")"
assert_eq "ttl-0 lease cannot be renewed" "7" "$rc"

seed_lease "$(lin_lease_node "$HANDLE" kyle "$NOW" 24)"
rc="$(lin_run "$S" "linear:acme/ENG#12" --lease-comment-id "999999999999")"
assert_eq "unknown handle → exit 7" "7" "$rc"
assert_contains "and names the handle" "$(lin_err)" "999999999999"

seed_lease '[]'
rc="$(lin_run "$S" "linear:acme/ENG#12" --lease-comment-id "$HANDLE")"
assert_eq "no lease on the item → exit 7" "7" "$rc"

lin_reset
rc="$(lin_run "$S" "linear:acme/OPS#5" --lease-comment-id "$HANDLE")"
assert_eq "undeclared team → exit 2" "2" "$rc"
assert_eq "and nothing was requested" "" "$(lin_requests)"

[[ $FAILED -eq 0 ]] || exit 1
