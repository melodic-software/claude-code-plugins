#!/usr/bin/env bash
# The host-defect record is the four-part shape, and the probe checks the
# published amplification rows.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$SCRIPT_DIR/token-leak-amplification.sh"
README="$SCRIPT_DIR/README.md"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_absent() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

body="$(cat "$README")"
assert_contains "the record states the claim" "$body" "**Claim:**"
assert_contains "the record states the basis" "$body" "**Basis:**"
assert_contains "the record states the as-of date" "$body" "**As of:** 2026-09-28."
assert_contains "the record states the recheck trigger" "$body" "**Recheck trigger:**"
assert_contains "recheck names the build bound" "$body" "26200.9550"
assert_contains "recheck names a Microsoft acknowledgement" "$body" "Microsoft acknowledgement"
assert_contains "the record points at the amplification probe" "$body" "token-leak-amplification.sh"
assert_absent "the record is not a park ledger" "$body" "true_impossible"
assert_absent "the record does not say parked" "$body" "Parked"
assert_absent "the record does not say unpaid" "$body" "unpaid"

out="$(bash "$PROBE" --self-test)"
rc=$?
assert_eq "self-test exits 0" "$rc" "0"
assert_contains "self-test reports the one-for-one line" "$out" "one-for-one"

amp="$(bash "$PROBE" --amplify 4 6)"
rc=$?
assert_eq "amplify exits 0" "$rc" "0"
assert_eq "four fires of the six-creator shape leak 24 tokens" "$amp" "24"

bash "$PROBE" --amplify -1 2 >/dev/null 2>&1
rc=$?
assert_eq "a non-numeric amplify fails closed" "$rc" "2"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]
