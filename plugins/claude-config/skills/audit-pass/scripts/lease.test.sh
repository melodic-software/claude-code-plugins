#!/usr/bin/env bash
# Regression tests for audit-pass/scripts/lease.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEASE="$SCRIPT_DIR/lease.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE=0

pass() { CASE=$((CASE + 1)); printf 'PASS: %s\n' "$1"; }
fail() { CASE=$((CASE + 1)); FAILED=$((FAILED + 1)); printf 'FAIL: %s\n  %s\n' "$1" "$2" >&2; }
assert_eq() { [[ "$2" == "$3" ]] && pass "$1" || fail "$1" "expected '$3', got '$2'"; }
assert_exit() { [[ "$2" == "$3" ]] && pass "$1" || fail "$1" "expected exit $3, got $2"; }

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed" >&2
  exit 0
fi

chmod +x "$LEASE"
LEASE_FILE="$TEST_TMPDIR/runs/key/run-1/lease"

# acquire on missing path
rc=0
OUT=$("$LEASE" acquire --lease-path "$LEASE_FILE" --run-id run-1) || rc=$?
assert_exit "acquire creates lease" 0 "$rc"
assert_eq "acquire prints owner_epoch" "acquired run_id=run-1 owner_epoch=1" "$OUT"
assert_eq "classify live after acquire" "live" "$("$LEASE" classify --lease-path "$LEASE_FILE")"

# second acquire refuses while live
rc=0
"$LEASE" acquire --lease-path "$LEASE_FILE" --run-id run-2 >/dev/null 2>&1 || rc=$?
assert_exit "live lease blocks second acquire" 2 "$rc"

# heartbeat + epoch fence
rc=0
OUT=$("$LEASE" heartbeat --lease-path "$LEASE_FILE" --run-id run-1 --owner-epoch 1) || rc=$?
assert_exit "heartbeat succeeds for holder" 0 "$rc"
assert_contains() {
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1" "expected to contain '$3' in '$2'" ;; esac
}
assert_contains "heartbeat updates timestamp" "$OUT" "heartbeat_at="

rc=0
"$LEASE" heartbeat --lease-path "$LEASE_FILE" --run-id run-1 --owner-epoch 0 >/dev/null 2>&1 || rc=$?
assert_exit "wrong owner_epoch is fenced" 2 "$rc"

# release tombstone
rc=0
OUT=$("$LEASE" release --lease-path "$LEASE_FILE" --run-id run-1) || rc=$?
assert_exit "release succeeds" 0 "$rc"
assert_eq "classify released after tombstone" "released" "$("$LEASE" classify --lease-path "$LEASE_FILE")"

# stale lease + adopt
STALE="$TEST_TMPDIR/stale/lease"
mkdir -p "$(dirname "$STALE")"
jq -n --argjson pid 1 \
  --arg started_at "2020-01-01T00:00:00Z" \
  --arg heartbeat_at "2020-01-01T00:00:00Z" \
  '{run_id:"old",pid:$pid,started_at:$started_at,heartbeat_at:$heartbeat_at,owner_epoch:2,state:"active"}' \
  >"$STALE"
assert_eq "old heartbeat is stale" "stale" "$("$LEASE" classify --lease-path "$STALE")"
rc=0
OUT=$("$LEASE" adopt --lease-path "$STALE" --run-id run-new --expected-epoch 2) || rc=$?
assert_exit "adopt stale lease" 0 "$rc"
assert_eq "classify live after adopt" "live" "$("$LEASE" classify --lease-path "$STALE")"
assert_eq "adopt increments epoch" "adopted run_id=run-new owner_epoch=3 (from 2)" "$OUT"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE"
  exit 0
fi
printf '\n%d of %d checks failed.\n' "$FAILED" "$CASE" >&2
exit 1
