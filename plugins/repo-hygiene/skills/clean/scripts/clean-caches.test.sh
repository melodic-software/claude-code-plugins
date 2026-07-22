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

# --- manifest / summary / apply-from-manifest / resume (issues #995, #1002) ---
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
assert_contains "manifest tags class+path" "$mani_body" "caches"
assert_contains "manifest carries the cache path" "$mani_body" ".pytest_cache"
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
