#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/renew-lease.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" "github:o/r#1" --lease-comment-id 1

# End-to-end: ttl-0 claim is born expired; renew-lease must refuse it (exit 7)
# rather than bumping renewed_at and reviving the dead handle. A live control
# claim on a second item must still renew.
TRACKER="$(cd "$(dirname "$S")" && pwd)/../../work-item-tracker.sh"

STORAGE="$(mktemp -d)"
BINDING="$(mktemp)"
jq -cn --arg dir "$STORAGE" \
  '{schema_version: "1.0", provider: "local-markdown", config: {lease_ttl_hours: 24, storage_dir: $dir}}' \
  >"$BINDING"
export WORK_ITEM_TRACKER_BINDING="$BINDING"

EXPIRED_ID="$(bash "$TRACKER" create-item --title "ttl-0 renew refuse" | jq -r '.id')"
LIVE_ID="$(bash "$TRACKER" create-item --title "live renew control" | jq -r '.id')"

EXPIRED_CLAIM="$(bash "$TRACKER" claim "$EXPIRED_ID" --ttl-hours 0)"
LIVE_CLAIM="$(bash "$TRACKER" claim "$LIVE_ID" --ttl-hours 24)"
EXPIRED_CID="$(jq -r '.lease_comment_id' <<<"$EXPIRED_CLAIM")"
LIVE_CID="$(jq -r '.lease_comment_id' <<<"$LIVE_CLAIM")"

expired_number="${EXPIRED_ID##*#}"
expired_file="$STORAGE/${expired_number}.md"
before_marker="$(grep -F 'work-item-lease' "$expired_file")"

set +e
bash "$TRACKER" renew-lease "$EXPIRED_ID" --lease-comment-id "$EXPIRED_CID" >/dev/null 2>&1
expired_rc=$?
set +e
assert_eq "renew-lease returns conflict (7) for a ttl-0 expired lease" "7" "$expired_rc"

after_marker="$(grep -F 'work-item-lease' "$expired_file")"
assert_eq "renew-lease does NOT revive the ttl-0 lease (marker unchanged)" "$before_marker" "$after_marker"

set +e
LIVE_OUT="$(bash "$TRACKER" renew-lease "$LIVE_ID" --lease-comment-id "$LIVE_CID")"
live_rc=$?
set +e
assert_eq "renew-lease succeeds (0) for a live lease" "0" "$live_rc"
assert_eq "renew-lease emits the live item id" "$LIVE_ID" "$(jq -r '.id' <<<"$LIVE_OUT")"

rm -rf "$STORAGE"
rm -f "$BINDING"
unset WORK_ITEM_TRACKER_BINDING

[[ $FAILED -eq 0 ]] || exit 1
