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

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: clean-caches.sh tests passed"
