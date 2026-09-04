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
# claim on a second item must still renew, and that renewal must reach the store.
TRACKER="$(cd "$(dirname "$S")" && pwd)/../../work-item-tracker.sh"
# The store assertions read leases back through the adapter's own parser.
# shellcheck source=common.sh
source "$(dirname "$S")/common.sh"

STORAGE="$(mktemp -d)"
BINDING="$(mktemp)"
jq -cn --arg dir "$STORAGE" \
  '{schema_version: "1.0", provider: "local-markdown", config: {lease_ttl_hours: 24, storage_dir: $dir}}' \
  >"$BINDING"
export WORK_ITEM_TRACKER_BINDING="$BINDING"

EXPIRED_JSON="$(bash "$TRACKER" create-item --title "ttl-0 renew refuse")"
LIVE_JSON="$(bash "$TRACKER" create-item --title "live renew control")"
EXPIRED_ID="$(jq -r '.id' <<<"$EXPIRED_JSON")"
LIVE_ID="$(jq -r '.id' <<<"$LIVE_JSON")"
# Recover each item's on-disk path from its own reported url: the tracker resolves
# the storage dir itself (and MSYS may translate it), so the outer $STORAGE is not
# necessarily where the files land, and a wrong path would quietly reduce the
# marker assertions below to comparing two empty greps.
EXPIRED_FILE="$(jq -r '.url' <<<"$EXPIRED_JSON" | sed 's#^file://##')"
LIVE_FILE="$(jq -r '.url' <<<"$LIVE_JSON" | sed 's#^file://##')"

EXPIRED_CLAIM="$(bash "$TRACKER" claim "$EXPIRED_ID" --ttl-hours 0)"
LIVE_CLAIM="$(bash "$TRACKER" claim "$LIVE_ID" --ttl-hours 24)"
EXPIRED_CID="$(jq -r '.lease_comment_id' <<<"$EXPIRED_CLAIM")"
LIVE_CID="$(jq -r '.lease_comment_id' <<<"$LIVE_CLAIM")"

before_marker="$(grep -F 'work-item-lease' "$EXPIRED_FILE")"
assert_contains "the ttl-0 claim stored the handle it reported" \
  "$before_marker" "\"lease_comment_id\":$EXPIRED_CID"

bash "$TRACKER" renew-lease "$EXPIRED_ID" --lease-comment-id "$EXPIRED_CID" >/dev/null 2>&1
expired_rc=$?
assert_eq "renew-lease returns conflict (7) for a ttl-0 expired lease" "7" "$expired_rc"

after_marker="$(grep -F 'work-item-lease' "$EXPIRED_FILE")"
assert_eq "renew-lease does NOT revive the ttl-0 lease (marker unchanged)" "$before_marker" "$after_marker"

# renewed_at is second-granular, so put a second between the claim and the
# renewal: without the gap a renewal that never reached the store is byte-for-byte
# the lease the claim wrote, and the store assertion below would pass on a lost write.
sleep 1
LIVE_OUT="$(bash "$TRACKER" renew-lease "$LIVE_ID" --lease-comment-id "$LIVE_CID")"
live_rc=$?
assert_eq "renew-lease succeeds (0) for a live lease" "0" "$live_rc"
assert_eq "renew-lease emits the live item id" "$LIVE_ID" "$(jq -r '.id' <<<"$LIVE_OUT")"

# The renewal must land in the STORE, not only on stdout: a lost write leaves the
# next reader on the original renewed_at, expiring a lease its holder renewed.
STORED_LEASE="$(wit_active_lease_json "$LIVE_FILE")"
assert_eq "renew-lease persists the renewed_at it reported" \
  "$(jq -r '.renewed_at' <<<"$LIVE_OUT")" "$(jq -r '.renewed_at' <<<"$STORED_LEASE")"
assert_eq "the renewal replaced the lease marker rather than appending one" "1" \
  "$(grep -cF 'work-item-lease' "$LIVE_FILE")"

# A store write that cannot run must fail the verb rather than report a renewal
# nothing can read back. A PATH shim denies the temp file the rewrite needs (the
# dispatcher on this path calls no mktemp of its own, so only the write is hit).
SHIM="$(mktemp -d)"
printf '#!/usr/bin/env bash\nexit 1\n' >"$SHIM/mktemp"
chmod +x "$SHIM/mktemp"
LEASE_BEFORE="$(wit_active_lease_json "$LIVE_FILE")"
PATH="$SHIM:$PATH" bash "$TRACKER" renew-lease "$LIVE_ID" --lease-comment-id "$LIVE_CID" >/dev/null 2>&1
assert_eq "a store write that cannot run fails the renewal (exit 1)" "1" "$?"
assert_eq "the failed renewal left the stored lease untouched" \
  "$LEASE_BEFORE" "$(wit_active_lease_json "$LIVE_FILE")"
rm -rf "$SHIM"

# Remove the store the items actually landed in as well as the one this suite
# asked for; on a host that translates the path they are not the same directory.
# The guard is not optional: LIVE_FILE comes from the created item's reported
# url, so any upstream failure leaves it empty or "null", and `dirname` of either
# is ".". Unguarded, this line asks rm to delete the runner's working directory,
# and only GNU rm's own refusal to remove "." stands in the way.
rm -rf "$STORAGE"
if [[ "$LIVE_FILE" == /* && -e "$LIVE_FILE" ]]; then
  rm -rf "$(dirname "$LIVE_FILE")"
fi
rm -f "$BINDING"
unset WORK_ITEM_TRACKER_BINDING

[[ $FAILED -eq 0 ]] || exit 1
