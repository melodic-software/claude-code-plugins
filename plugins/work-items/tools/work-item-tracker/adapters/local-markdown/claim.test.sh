#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/claim.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" "github:o/r#1"

# The claim record is derived from the lease claim.sh stores, so pin the two
# together: the optional fields the record reports must be the ones the marker
# carries, and an absent --session-id must report as an explicit null.
ADAPTER="$(dirname "$S")"
STORE="$(mktemp -d)"
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
rm -rf "$STORE"

[[ $FAILED -eq 0 ]] || exit 1
