#!/usr/bin/env bash
# Local-markdown lease/assignee-integrity behaviors that the abstract conformance
# suite cannot assert (it runs against every adapter, and these two behaviors are
# local-markdown-specific — the GitHub adapter has reclaim and a real assignee
# field). Covers: (1) an expired lease returns the item to the frontier even though
# this adapter has no reclaim, and (2) a failed assignee write fails the claim and
# rolls the just-appended lease marker back, leaving no orphaned marker.
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER="$SCRIPT_DIR/../../work-item-tracker.sh"
source "$SCRIPT_DIR/../../tests/lib.sh"

# --- Finding 1: expired lease reappears in the frontier (end-to-end, core CLI) ---

STORAGE="$(mktemp -d)"
BINDING="$(mktemp)"
jq -cn --arg dir "$STORAGE" \
  '{schema_version: "1.0", provider: "local-markdown", config: {lease_ttl_hours: 24, storage_dir: $dir}}' \
  >"$BINDING"
export WORK_ITEM_TRACKER_BINDING="$BINDING"

A_ID="$(bash "$TRACKER" create-item --title "expired-lease item" | jq -r '.id')"
B_ID="$(bash "$TRACKER" create-item --title "live-lease item" | jq -r '.id')"

# A: ttl 0 → the lease is expired the instant it is written.
bash "$TRACKER" claim "$A_ID" --ttl-hours 0 >/dev/null
# B: a live lease is the control — it must stay out of the frontier.
bash "$TRACKER" claim "$B_ID" --ttl-hours 24 >/dev/null

FRONTIER_IDS="$(bash "$TRACKER" list-frontier | jq -c '[.items[].id]')"
assert_contains "expired-lease A returns to the frontier" "$FRONTIER_IDS" "$A_ID"
assert_not_contains "live-lease B stays out of the frontier" "$FRONTIER_IDS" "$B_ID"

# get-item keeps the stored assignee raw (parity with the GitHub adapter) — the
# projection is scoped to list/frontier derivation, not a stored mutation.
A_ASSIGNEES="$(bash "$TRACKER" get-item "$A_ID" | jq -r '.assignees | length')"
assert_eq "get-item leaves the expired-lease assignee stored" "1" "$A_ASSIGNEES"

rm -rf "$STORAGE"
rm -f "$BINDING"
unset WORK_ITEM_TRACKER_BINDING

# --- Finding 2: a failed assignee write fails the claim and rolls the marker back ---

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

write_item() {
  cat >"$1" <<'EOF'
---
id: "local-markdown:local/markdown#1"
title: "rollback fixture"
state: "open"
assignees: []
labels: []
type: null
parent: null
url: null
---

body
EOF
}

LEASE_JSON='{"schema_version":"1.0","holder":"tester","acquired_at":"2020-01-01T00:00:00Z","renewed_at":"2020-01-01T00:00:00Z","ttl_hours":24,"lease_comment_id":1}'
MARKER_LINE="${WIT_LEASE_MARKER}${LEASE_JSON} -->"

# Happy path (real wit_fm_set): both writes land and the helper reports success.
OK_FILE="$(mktemp)"
write_item "$OK_FILE"
wit_claim_write "$OK_FILE" "$MARKER_LINE" '["tester"]'
assert_eq "successful claim write returns 0" "0" "$?"
if grep -qxF -- "$MARKER_LINE" "$OK_FILE"; then
  pass "successful claim write keeps the lease marker"
else
  fail "successful claim write keeps the lease marker" "marker present" "marker missing"
fi
assert_eq "successful claim write records the assignee" '["tester"]' "$(wit_fm_field "$OK_FILE" assignees)"
rm -f "$OK_FILE"

# Failure path: simulate a failed assignee write. The helper must fail AND roll the
# just-appended marker back, leaving the store as if the claim never happened.
FAIL_FILE="$(mktemp)"
write_item "$FAIL_FILE"
wit_fm_set() { return 1; }
wit_claim_write "$FAIL_FILE" "$MARKER_LINE" '["tester"]'
assert_eq "failed assignee write fails the claim" "1" "$?"
if grep -qxF -- "$MARKER_LINE" "$FAIL_FILE"; then
  fail "failed assignee write rolls the lease marker back" "no marker" "orphaned marker present"
else
  pass "failed assignee write rolls the lease marker back"
fi
assert_eq "failed claim leaves assignees empty" "[]" "$(wit_fm_field "$FAIL_FILE" assignees)"
rm -f "$FAIL_FILE"

# Failure path where the rollback itself cannot run (mktemp fails — the same class
# of store condition). The claim still fails, and the helper WARNS that the marker
# may be orphaned instead of silently claiming a clean rollback.
FAIL2_FILE="$(mktemp)"
write_item "$FAIL2_FILE"
# Invoked indirectly by the sourced wit_claim_write, which shellcheck cannot see
# across the source boundary (it resolves mktemp there as the external command).
# shellcheck disable=SC2329
mktemp() { return 1; }
WARN="$(wit_claim_write "$FAIL2_FILE" "$MARKER_LINE" '["tester"]' 2>&1)"
RC=$?
unset -f mktemp
assert_eq "rollback-blocked claim still fails" "1" "$RC"
assert_contains "rollback failure is reported, not silently claimed" "$WARN" "rollback of the lease marker failed"
if grep -qxF -- "$MARKER_LINE" "$FAIL2_FILE"; then
  pass "rollback-blocked claim leaves the marker (warned, not silent)"
else
  fail "rollback-blocked claim leaves the marker (warned, not silent)" "marker present" "marker missing"
fi
rm -f "$FAIL2_FILE"

[[ $FAILED -eq 0 ]] || exit 1
