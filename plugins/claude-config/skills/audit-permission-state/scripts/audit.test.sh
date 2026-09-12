#!/usr/bin/env bash
# Regression tests for audit.sh (self-contained — ships with the plugin).
#
# audit.sh composes the stage scripts; it owns no checks of its own. These tests
# cover what composition can get wrong: running the inventory more than once,
# widening the default past read-only, firing a priced lane nobody asked for, and
# swallowing a stage's readability record on the way through.
#
# Stage behavior itself belongs to each stage's own suite. Nothing here asserts a
# finding.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/audit.sh"

FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3" ;;
  *) pass "$1" ;;
  esac
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
count_matching() {
  printf '%s\n' "$1" | grep -c -- "$2" || true
}

# --- Case 1: --help ----------------------------------------------------------
rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help names the read-only default" "$OUT" "every read-only stage"
assert_contains "--help prices the oracle" "$OUT" "SPAWNS A REAL"
assert_contains "--help warns about critique" "$OUT" "truncate or return nothing"

# --- Case 2: an unknown argument fails loudly --------------------------------
# A typo'd flag must not silently degrade to the default breadth, which would run
# a different audit than the one that was asked for.
rc=0
ERR=$(bash "$SCRIPT" --not-a-flag 2>&1) || rc=$?
assert_exit "an unknown argument exits 2" 2 "$rc"
assert_contains "and names the argument" "$ERR" "--not-a-flag"

# --- Case 3: the default runs every read-only stage, and no priced lane -------
rc=0
OUT=$(bash "$SCRIPT") || rc=$?
assert_exit "a bare run exits 0" 0 "$rc"
assert_contains "the default runs the inventory" "$OUT" "===== Scopes and surfaces ====="
assert_contains "the default runs the merge" "$OUT" "===== Effective set ====="
assert_contains "the default runs the entry diff" "$OUT" "===== Auto-mode entry diff ====="
assert_contains "the default runs the plane lint" "$OUT" "===== Permission-plane lint ====="
assert_contains "the default runs managed conformance" "$OUT" "===== Managed conformance ====="
assert_contains "the default runs the block lint" "$OUT" "===== autoMode block lint ====="

# Every stage that ran must have reported a summary; a section header with no
# summary beneath it is a stage that died quietly.
assert_contains "the merge summarized" "$OUT" "merge summary"
assert_contains "the entry diff summarized" "$OUT" "entry-diff summary"
assert_contains "the plane lint summarized" "$OUT" "lint summary"
assert_contains "managed conformance summarized" "$OUT" "managed conformance summary"
assert_contains "the block lint summarized" "$OUT" "automode summary"

# --- Case 4: the inventory is walked once, not once per consumer --------------
# The whole reason this script exists. The inventory's local-scope NOTE is
# emitted exactly once per walk, so counting it counts the walks.
assert_eq "the inventory ran exactly once" 1 "$(count_matching "$OUT" 'NOTE: local scope anchored')"

# --- Case 5: flags narrow, never widen ---------------------------------------
OUT_SCOPES=$(bash "$SCRIPT" --scopes)
assert_contains "--scopes runs the inventory" "$OUT_SCOPES" "===== Scopes and surfaces ====="
assert_not_contains "--scopes stops before the merge" "$OUT_SCOPES" "===== Effective set ====="
assert_not_contains "--scopes stops before the lint" "$OUT_SCOPES" "===== Permission-plane lint ====="

OUT_LINT=$(bash "$SCRIPT" --lint)
assert_contains "--lint runs the lint" "$OUT_LINT" "lint summary"
assert_not_contains "--lint does not run the entry diff" "$OUT_LINT" "entry-diff summary"
assert_not_contains "--lint does not run managed conformance" "$OUT_LINT" "managed conformance summary"

OUT_MANAGED=$(bash "$SCRIPT" --managed)
assert_contains "--managed runs managed conformance" "$OUT_MANAGED" "managed conformance summary"
assert_not_contains "--managed does not run the lint" "$OUT_MANAGED" "lint summary"

# --- Case 6: --block needs no inventory --------------------------------------
# The block lint reads the CLI rather than stdin, so asking for it alone must not
# drag a scope walk along.
OUT_BLOCK=$(bash "$SCRIPT" --block)
assert_contains "--block runs the block lint" "$OUT_BLOCK" "automode summary"
assert_not_contains "--block skips the inventory entirely" "$OUT_BLOCK" "===== Scopes and surfaces ====="

# --- Case 7: the priced lanes stay opt-in ------------------------------------
# Neither may appear in a default run. --oracle spawns a real session; --critique
# shells out to a slow, unreliable subcommand. A default that fired either would
# charge the operator for something they did not ask for.
assert_not_contains "the default names no oracle section" "$OUT" "oracle"
assert_not_contains "the default names no critique section" "$OUT" "critique"

# --- Case 8: a stage's readability record survives composition ---------------
# audit.sh drops the entry diff's duplicated pass-through NOTEs, which the two
# sections above it already printed. It must not drop that stage's own records:
# the status token is how an unreadable scope is distinguished from a clean one,
# and losing it here would reintroduce the defect the token exists to fix.
assert_contains "the entry diff keeps its status token" "$OUT" "entry-diff summary allow_before="
assert_contains "the plane lint keeps its status token" "$OUT" "checks_run=9 status="
assert_contains "the diff keeps its own DIFF-NOTE records" "$OUT" "DIFF-NOTE:"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
