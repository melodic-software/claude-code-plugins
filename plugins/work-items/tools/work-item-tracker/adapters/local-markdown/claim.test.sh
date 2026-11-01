#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claim.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" "github:o/r#1"

# The claim record is derived from the lease claim.sh stores, so pin the two
# together: the optional fields the record reports must be the ones the marker
# carries, and an absent --session-id must report as an explicit null.
ADAPTER="$(dirname "$S")"
STORE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
ITEM="$(WIT_STORAGE_DIR="$STORE" bash "$ADAPTER/create-item.sh" --title "claim record")"
ITEM_FILE="$(jq -r '.url' <<<"$ITEM" | sed 's#^file://##')"
RECORD="$(WIT_STORAGE_DIR="$STORE" bash "$S" "$(jq -r '.id' <<<"$ITEM")" \
  --ttl-hours 24 --ttl-minutes 30 --session-id sess-1)"
STORED="$(grep -F 'work-item-lease' "$ITEM_FILE")"
assert_eq "the claim record carries the session id it was given" "sess-1" "$(jq -r '.session_id' <<<"$RECORD")"
assert_eq "the claim record carries the sub-hour ttl it was given" "30" "$(jq -r '.ttl_minutes' <<<"$RECORD")"
assert_contains "the stored lease carries the same session id" "$STORED" '"session_id":"sess-1"'
assert_contains "the stored lease carries the handle the record reports" \
  "$STORED" "\"lease_comment_id\":$(jq -r '.lease_comment_id' <<<"$RECORD")"

ITEM2="$(WIT_STORAGE_DIR="$STORE" bash "$ADAPTER/create-item.sh" --title "no session")"
RECORD2="$(WIT_STORAGE_DIR="$STORE" bash "$S" "$(jq -r '.id' <<<"$ITEM2")" --ttl-hours 24)"
assert_eq "an absent --session-id reports as an explicit null" "null" "$(jq -r '.session_id' <<<"$RECORD2")"
assert_eq "an absent --ttl-minutes is omitted, not zero" "null" "$(jq -r '.ttl_minutes // "null"' <<<"$RECORD2")"
# A TTL over the lease cap is refused before the item file is written.
ITEM3="$(WIT_STORAGE_DIR="$STORE" bash "$ADAPTER/create-item.sh" --title "over cap")"
ITEM3_FILE="$(jq -r '.url' <<<"$ITEM3" | sed 's#^file://##')"
BEFORE="$(cat "$ITEM3_FILE")"
WIT_STORAGE_DIR="$STORE" assert_usage_error "$S" "$(jq -r '.id' <<<"$ITEM3")" --ttl-hours 169
assert_eq "a refused over-cap claim leaves the item file unchanged" "$BEFORE" "$(cat "$ITEM3_FILE")"

# --phase writes the field into the stored lease; no --phase stores none (an
# implementation claim); an unknown phase is refused before the item file is written.
ITEM4="$(WIT_STORAGE_DIR="$STORE" bash "$ADAPTER/create-item.sh" --title "triage claim")"
ITEM4_FILE="$(jq -r '.url' <<<"$ITEM4" | sed 's#^file://##')"
WIT_STORAGE_DIR="$STORE" bash "$S" "$(jq -r '.id' <<<"$ITEM4")" --ttl-hours 24 --phase triage >/dev/null
assert_contains "claim --phase triage stores the phase in the lease" \
  "$(grep -F 'work-item-lease' "$ITEM4_FILE")" '"phase":"triage"'
assert_not_contains "a claim with no --phase stores no phase field" "$STORED" '"phase"'
BEFORE="$(cat "$ITEM3_FILE")"
WIT_STORAGE_DIR="$STORE" assert_usage_error "$S" "$(jq -r '.id' <<<"$ITEM3")" --ttl-hours 24 --phase review
WIT_STORAGE_DIR="$STORE" assert_usage_error "$S" "$(jq -r '.id' <<<"$ITEM3")" --ttl-hours 24 --phase ""
assert_eq "a refused phase leaves the item file unchanged" "$BEFORE" "$(cat "$ITEM3_FILE")"
rm -rf "$STORE"

[[ $FAILED -eq 0 ]] || exit 1
