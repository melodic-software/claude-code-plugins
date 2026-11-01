#!/usr/bin/env bash
# Self-contained tests for lib/persist-report.sh (no external test lib — ships with the plugin).
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git remote` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
CDPATH=

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/persist-report.sh"
STATE_KEY="$SCRIPT_DIR/state-key.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0
pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}

REPO_A="$TEST_TMPDIR/alpha"
REPO_B="$TEST_TMPDIR/beta"
mkdir -p "$REPO_A" "$REPO_B"
git -C "$REPO_A" init --quiet >/dev/null 2>&1
git -C "$REPO_A" remote add origin https://github.com/example/alpha.git >/dev/null 2>&1
git -C "$REPO_B" init --quiet >/dev/null 2>&1
git -C "$REPO_B" remote add origin https://github.com/example/beta.git >/dev/null 2>&1

KEY_A="$(bash "$STATE_KEY" --root "$REPO_A")"
KEY_B="$(bash "$STATE_KEY" --root "$REPO_B")"

REPORT1="$TEST_TMPDIR/report1.md"
REPORT2="$TEST_TMPDIR/report2.md"
printf 'Resolved root: alpha\nfirst\n' >"$REPORT1"
printf 'Resolved root: alpha\nsecond\n' >"$REPORT2"

# --- 1. first write lands at <plugin-data>/<component>/<state-key>/last-audit.md
DATA="$TEST_TMPDIR/data"
mkdir -p "$DATA"
EXPECTED="$DATA/audit-prompting-postures/$KEY_A/last-audit.md"
out="$(bash "$SCRIPT" --plugin-data "$DATA" --component audit-prompting-postures --report "$REPORT1" --root "$REPO_A")"
rc=$?
assert_eq "first write exits 0" "0" "$rc"
assert_eq "first write prints the final path" "$EXPECTED" "$out"
assert_eq "first write carries the report body" "$(cat "$REPORT1")" "$(cat "$EXPECTED" 2>/dev/null)"

# --- 2. a second write to the same key replaces the file and leaves no staging file
out="$(bash "$SCRIPT" --plugin-data "$DATA" --component audit-prompting-postures --report "$REPORT2" --root "$REPO_A")"
rc=$?
assert_eq "overwrite exits 0" "0" "$rc"
assert_eq "overwrite prints the same path" "$EXPECTED" "$out"
assert_eq "overwrite replaces the body" "$(cat "$REPORT2")" "$(cat "$EXPECTED" 2>/dev/null)"
assert_eq "overwrite leaves exactly one file in the keyed directory" "last-audit.md" \
  "$(ls -A "$DATA/audit-prompting-postures/$KEY_A")"

# --- 3. the body can come from stdin
out="$(printf 'from stdin\n' | bash "$SCRIPT" --plugin-data "$DATA" --component audit-instructions --report - --root "$REPO_A")"
rc=$?
assert_eq "stdin write exits 0" "0" "$rc"
assert_eq "stdin write lands under its own component" "$DATA/audit-instructions/$KEY_A/last-audit.md" "$out"
assert_eq "stdin write carries the body" "from stdin" "$(cat "$DATA/audit-instructions/$KEY_A/last-audit.md" 2>/dev/null)"

# --- 4. two repositories get two keys, so neither overwrites the other
out="$(bash "$SCRIPT" --plugin-data "$DATA" --component audit-prompting-postures --report "$REPORT1" --root "$REPO_B")"
assert_eq "a second repository writes under its own key" "$DATA/audit-prompting-postures/$KEY_B/last-audit.md" "$out"
assert_eq "the first repository's report is untouched" "$(cat "$REPORT2")" "$(cat "$EXPECTED" 2>/dev/null)"

# --- 5. rejected arguments exit 2 and write nothing
# Each case gets a fresh case directory holding one empty `data` root, and runs
# from inside that root. A write that escaped the checks would land in the case
# directory: under `data` for a relative --plugin-data or a '..' --plugin-data,
# beside it for a '..' component. So the case directory must still hold only
# an empty `data`.
expect_rejected() {
  local name="$1"
  shift
  local case_dir="$TEST_TMPDIR/reject-$CASES"
  local root="$case_dir/data"
  mkdir -p "$root"
  local args=("$@")
  local i
  for i in "${!args[@]}"; do
    args[i]="${args[i]//@ROOT@/$root}"
  done
  (cd "$root" && bash "$SCRIPT" "${args[@]}" </dev/null >/dev/null 2>&1)
  local rc=$?
  assert_eq "$name: exits 2" "2" "$rc"
  assert_eq "$name: writes nothing" "data" "$(ls -A "$case_dir")"
  assert_eq "$name: leaves the data root empty" "" "$(ls -A "$root")"
}

expect_rejected "missing --plugin-data" \
  --component audit-prompting-postures --report "$REPORT1" --root "$REPO_A"
expect_rejected "empty --plugin-data" \
  --plugin-data "" --component audit-prompting-postures --report "$REPORT1" --root "$REPO_A"
expect_rejected "relative --plugin-data" \
  --plugin-data "relative/data" --component audit-prompting-postures --report "$REPORT1" --root "$REPO_A"
expect_rejected "--plugin-data with a '..' component" \
  --plugin-data "@ROOT@/sub/../escape" --component audit-prompting-postures --report "$REPORT1" --root "$REPO_A"
expect_rejected "--plugin-data ending in '..'" \
  --plugin-data "@ROOT@/sub/.." --component audit-prompting-postures --report "$REPORT1" --root "$REPO_A"
expect_rejected "missing --component" \
  --plugin-data "@ROOT@" --report "$REPORT1" --root "$REPO_A"
expect_rejected "--component with a separator" \
  --plugin-data "@ROOT@" --component "audit/prompting" --report "$REPORT1" --root "$REPO_A"
expect_rejected "--component of '..'" \
  --plugin-data "@ROOT@" --component ".." --report "$REPORT1" --root "$REPO_A"
expect_rejected "--component with a leading dot" \
  --plugin-data "@ROOT@" --component ".hidden" --report "$REPORT1" --root "$REPO_A"
expect_rejected "missing --report" \
  --plugin-data "@ROOT@" --component audit-prompting-postures --root "$REPO_A"
expect_rejected "--report that does not exist" \
  --plugin-data "@ROOT@" --component audit-prompting-postures --report "$TEST_TMPDIR/absent.md" --root "$REPO_A"
expect_rejected "empty report on stdin" \
  --plugin-data "@ROOT@" --component audit-prompting-postures --report - --root "$REPO_A"
expect_rejected "unknown argument" \
  --plugin-data "@ROOT@" --component audit-prompting-postures --report "$REPORT1" --bogus

printf '\n%d case(s), %d failed\n' "$CASES" "$FAILED"
if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi
exit 0
