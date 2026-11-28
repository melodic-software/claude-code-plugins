#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
# test-scope: plugins/work-items/tools/work-item-tracker/adapters/local-markdown/*
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/renew-lease.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" "github:o/r#1" --lease-comment-id 1

TRACKER="$(dirname "$S")/../../work-item-tracker.sh"
# shellcheck source=common.sh
source "$(dirname "$S")/common.sh"

STORAGE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
BINDING="$(mktemp "$TMP_ROOT/f.XXXXXX")"
jq -cn --arg dir "$STORAGE" \
  '{schema_version: "1.0", provider: "local-markdown", config: {lease_ttl_hours: 24, storage_dir: $dir}}' \
  >"$BINDING"
export WORK_ITEM_TRACKER_BINDING="$BINDING"

EXPIRED_JSON="$(bash "$TRACKER" create-item --title "ttl-0 renew refuse")"
LIVE_JSON="$(bash "$TRACKER" create-item --title "live renew control")"
EXPIRED_ID="$(jq -r '.id' <<<"$EXPIRED_JSON")"
LIVE_ID="$(jq -r '.id' <<<"$LIVE_JSON")"
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

sleep 1
LIVE_OUT="$(bash "$TRACKER" renew-lease "$LIVE_ID" --lease-comment-id "$LIVE_CID")"
live_rc=$?
assert_eq "renew-lease succeeds (0) for a live lease" "0" "$live_rc"
assert_eq "renew-lease emits the live item id" "$LIVE_ID" "$(jq -r '.id' <<<"$LIVE_OUT")"

STORED_LEASE="$(wit_active_lease_json "$LIVE_FILE")"
assert_eq "renew-lease persists the renewed_at it reported" \
  "$(jq -r '.renewed_at' <<<"$LIVE_OUT")" "$(jq -r '.renewed_at' <<<"$STORED_LEASE")"
assert_eq "the renewal replaced the lease marker rather than appending one" "1" \
  "$(grep -cF 'work-item-lease' "$LIVE_FILE")"

SHIM="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
printf '#!/usr/bin/env bash\nexit 1\n' >"$SHIM/mktemp"
chmod +x "$SHIM/mktemp"
LEASE_BEFORE="$(wit_active_lease_json "$LIVE_FILE")"
PATH="$SHIM:$PATH" bash "$TRACKER" renew-lease "$LIVE_ID" --lease-comment-id "$LIVE_CID" >/dev/null 2>&1
assert_eq "a store write that cannot run fails the renewal (exit 1)" "1" "$?"
assert_eq "the failed renewal left the stored lease untouched" \
  "$LEASE_BEFORE" "$(wit_active_lease_json "$LIVE_FILE")"
rm -rf "$SHIM"

PHASE_JSON="$(bash "$TRACKER" create-item --title "triage renew keeps phase")"
PHASE_ID="$(jq -r '.id' <<<"$PHASE_JSON")"
PHASE_FILE="$(jq -r '.url' <<<"$PHASE_JSON" | sed 's#^file://##')"
PHASE_CID="$(bash "$TRACKER" claim "$PHASE_ID" --ttl-hours 24 --phase triage | jq -r '.lease_comment_id')"
assert_eq "claim --phase triage stores the phase" "triage" "$(jq -r '.phase' <<<"$(wit_active_lease_json "$PHASE_FILE")")"
sleep 1
PHASE_OUT="$(bash "$TRACKER" renew-lease "$PHASE_ID" --lease-comment-id "$PHASE_CID")"
assert_eq "renew-lease on the triage lease succeeds (0)" "0" "$?"
PHASE_LEASE="$(wit_active_lease_json "$PHASE_FILE")"
assert_eq "renew-lease keeps the phase" "triage" "$(jq -r '.phase' <<<"$PHASE_LEASE")"
assert_eq "the kept-phase lease carries the renewed_at it reported" \
  "$(jq -r '.renewed_at' <<<"$PHASE_OUT")" "$(jq -r '.renewed_at' <<<"$PHASE_LEASE")"

rm -rf "$STORAGE"
if [[ "$LIVE_FILE" == /* && -e "$LIVE_FILE" ]]; then
  rm -rf "$(dirname "$LIVE_FILE")"
fi
rm -f "$BINDING"
unset WORK_ITEM_TRACKER_BINDING

[[ $FAILED -eq 0 ]] || exit 1
