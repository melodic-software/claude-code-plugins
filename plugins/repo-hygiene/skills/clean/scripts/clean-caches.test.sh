#!/usr/bin/env bash
# Tests for clean-caches.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

CLEAN="$SCRIPT_DIR/clean-caches.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

git init "$TEST_TMPDIR/repo" >/dev/null 2>&1
git -C "$TEST_TMPDIR/repo" config user.email "t@example.com"
git -C "$TEST_TMPDIR/repo" config user.name "Test"
mkdir -p "$TEST_TMPDIR/repo/.pytest_cache"
echo x >"$TEST_TMPDIR/repo/.pytest_cache/x"
mkdir -p "$TEST_TMPDIR/repo/node_modules/nm"
echo n >"$TEST_TMPDIR/repo/node_modules/nm/n"

run_clean() {
  GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" \
    bash -c "cd '$TEST_TMPDIR/repo' && bash '$CLEAN' $*"
}

out="$(run_clean)"
assert_contains "dry-run default planned" "$out" "Planned remove: .pytest_cache"
assert_file_exists "dry-run leaves cache" "$TEST_TMPDIR/repo/.pytest_cache/x"

out="$(run_clean --apply)"
assert_contains "apply removes cache" "$out" "Removed: .pytest_cache"
assert_file_absent "cache deleted after apply" "$TEST_TMPDIR/repo/.pytest_cache/x"

out="$(run_clean --dry-run)"
assert_not_contains "node_modules skipped" "$out" "node_modules"

# --- manifest / summary / apply-from-manifest / resume ---
# Fresh repo so progressive mutation above does not bleed into these cases.
git init "$TEST_TMPDIR/r2" >/dev/null 2>&1
git -C "$TEST_TMPDIR/r2" config user.email "t@example.com"
git -C "$TEST_TMPDIR/r2" config user.name "Test"
mkdir -p "$TEST_TMPDIR/r2/.pytest_cache"
echo x >"$TEST_TMPDIR/r2/.pytest_cache/x"
MANI="$TEST_TMPDIR/r2.manifest"

run_r2() {
  bash -c "cd '$TEST_TMPDIR/r2' && bash '$CLEAN' $*"
}

out="$(run_r2 --dry-run --manifest "$MANI")"
assert_contains "dry-run prints manifest path" "$out" "Manifest: $MANI"
assert_contains "dry-run planned summary" "$out" "Summary: planned=1 bytes="
assert_file_exists "manifest written" "$MANI"
mani_body="$(cat "$MANI")"
# Structural pin: the manifest is a consumed contract downstream tooling parses,
# so assert the exact <class>\t<bytes>\t<relpath> shape, not just substrings.
if grep -qE "^caches"$'\t'"[0-9]+"$'\t'"\.pytest_cache$" "$MANI"; then
  pass "manifest line is class<TAB>bytes<TAB>path"
else
  fail "manifest line format" "caches<TAB><int><TAB>.pytest_cache" "$mani_body"
fi
assert_file_exists "dry-run does not mutate" "$TEST_TMPDIR/r2/.pytest_cache/x"

out="$(run_r2 --apply --manifest "$MANI")"
rc=$?
assert_contains "apply-from-manifest removes" "$out" "Removed: .pytest_cache"
assert_contains "apply summary shape" "$out" "Summary: removed=1 failed=0 bytes="
assert_exit "apply exit 0" 0 "$rc"
assert_file_absent "cache gone after apply" "$TEST_TMPDIR/r2/.pytest_cache/x"

# Resume: re-applying the spent manifest is idempotent — nothing removed, no
# failures, clean exit (a killed apply just re-runs the same command).
out="$(run_r2 --apply --manifest "$MANI")"
rc=$?
assert_contains "resume removes nothing" "$out" "Summary: removed=0 failed=0 bytes=0"
assert_exit "resume exit 0" 0 "$rc"

# The manifest is an untrusted --apply surface (a caller supplies it, or a
# concurrent process alters it). Three hardening guards:

# 1. Containment — an entry escaping the repo (`..`) is rejected, never removed,
#    and counts as a failure (fail closed). The external victim survives.
mkdir -p "$TEST_TMPDIR/outside_victim"
echo v >"$TEST_TMPDIR/outside_victim/keep"
printf 'caches\t1\t../outside_victim\n' >"$TEST_TMPDIR/r2.escape.manifest"
out="$(run_r2 --apply --manifest "$TEST_TMPDIR/r2.escape.manifest" 2>&1)"
rc=$?
assert_contains "escaping entry rejected" "$out" "Rejected (outside repo): ../outside_victim"
assert_contains "rejection counts as failure" "$out" "Summary: removed=0 failed=1 bytes=0"
assert_exit "escape apply exits non-zero" 1 "$rc"
assert_file_exists "external victim preserved" "$TEST_TMPDIR/outside_victim/keep"

# 2. Byte field as data — a non-numeric byte field must NOT reach Bash arithmetic
#    (which evaluates array subscripts recursively). The payload would `touch` a
#    sentinel if evaluated; the guard coerces it to 0, so the path still removes
#    and the sentinel never appears.
mkdir -p "$TEST_TMPDIR/r2/.ruff_cache"
echo r >"$TEST_TMPDIR/r2/.ruff_cache/r"
SENTINEL="$TEST_TMPDIR/injected"
# The `$(...)` MUST stay literal in the manifest — expanding it here would defeat
# the test. shellcheck disable=SC2016 (intentional single quotes).
# shellcheck disable=SC2016
printf 'caches\tx[$(touch %s)]\t.ruff_cache\n' "$SENTINEL" >"$TEST_TMPDIR/r2.inject.manifest"
out="$(run_r2 --apply --manifest "$TEST_TMPDIR/r2.inject.manifest")"
rc=$?
assert_file_absent "arithmetic injection did not execute" "$SENTINEL"
assert_contains "malformed-byte entry still removes" "$out" "Removed: .ruff_cache"
assert_exit "inject apply exit 0" 0 "$rc"

# 3. Fail closed on an unreadable/missing manifest — silently doing nothing and
#    exiting 0 would let automation treat a mistyped path as a successful sweep.
out="$(run_r2 --apply --manifest "$TEST_TMPDIR/does-not-exist.manifest" 2>&1)"
rc=$?
assert_contains "missing manifest reported" "$out" "manifest not readable"
assert_exit "missing manifest exits non-zero" 1 "$rc"

# rm-failure accounting: a manifest entry rm cannot remove must count failed and
# force a non-zero exit. Deterministic only where the FS enforces a write-denied
# parent (real POSIX / Linux CI); Cygwin/MSYS ignores it, so probe and skip.
mkdir -p "$TEST_TMPDIR/r2/.mypy_cache/inner"
echo y >"$TEST_TMPDIR/r2/.mypy_cache/inner/y"
chmod a-w "$TEST_TMPDIR/r2/.mypy_cache" 2>/dev/null || true
if rm -rf "$TEST_TMPDIR/r2/.mypy_cache/inner" 2>/dev/null; then
  chmod u+w "$TEST_TMPDIR/r2/.mypy_cache" 2>/dev/null || true
  rm -rf "$TEST_TMPDIR/r2/.mypy_cache" 2>/dev/null || true
  skip_case "rm-failure accounting — FS does not enforce write-denied parent here"
else
  printf 'caches\t4096\t.mypy_cache/inner\n' >"$TEST_TMPDIR/r2.fail.manifest"
  out="$(run_r2 --apply --manifest "$TEST_TMPDIR/r2.fail.manifest")"
  rc=$?
  assert_contains "failure counted" "$out" "Summary: removed=0 failed=1 bytes=0"
  assert_exit "apply exits non-zero on failure" 1 "$rc"
  chmod u+w "$TEST_TMPDIR/r2/.mypy_cache" 2>/dev/null || true
fi

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: clean-caches.sh tests passed"
