#!/usr/bin/env bash
# Tests for scan.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

SCAN="$SCRIPT_DIR/scan.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

rc=0
bash "$SCAN" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

git init "$TEST_TMPDIR/repo" >/dev/null 2>&1
git -C "$TEST_TMPDIR/repo" config user.email "t@example.com"
git -C "$TEST_TMPDIR/repo" config user.name "Test"
mkdir -p "$TEST_TMPDIR/repo/.pytest_cache"
echo x >"$TEST_TMPDIR/repo/.pytest_cache/x"
git -C "$TEST_TMPDIR/repo" add .pytest_cache/x
git -C "$TEST_TMPDIR/repo" commit -m "tracked cache" >/dev/null
mkdir -p "$TEST_TMPDIR/repo/node_modules/pkg"
echo junk >"$TEST_TMPDIR/repo/node_modules/pkg/j"

out="$(GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$SCAN'")"
assert_not_contains "protected node_modules not inventoried" "$out" "node_modules"

git -C "$TEST_TMPDIR/repo" rm -r --cached .pytest_cache >/dev/null 2>&1
mkdir -p "$TEST_TMPDIR/repo/.ruff_cache"
echo y >"$TEST_TMPDIR/repo/.ruff_cache/y"

out="$(GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$SCAN'")"
assert_contains "finds untracked cache" "$out" ".ruff_cache"
assert_contains "emits category" "$out" "Category:"
assert_contains "emits total" "$out" "Total reclaimable:"

# Single pruned-walk engine: a build dir NESTED inside a pruned tree
# (node_modules) is never descended into, while a top-level build dir still
# enumerates. This proves the walk prunes rather than merely filters output.
mkdir -p "$TEST_TMPDIR/repo/node_modules/pkg/bin"
echo z >"$TEST_TMPDIR/repo/node_modules/pkg/bin/z"
mkdir -p "$TEST_TMPDIR/repo/src/bin"
echo z >"$TEST_TMPDIR/repo/src/bin/z"
out="$(GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$SCAN'")"
assert_contains "top-level build dir inventoried" "$out" "src/bin"
assert_not_contains "build dir under pruned node_modules skipped" "$out" "node_modules/pkg/bin"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: scan.sh tests passed"
