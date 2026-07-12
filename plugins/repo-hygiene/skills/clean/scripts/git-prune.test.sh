#!/usr/bin/env bash
# Tests for git-prune.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

PRUNE="$SCRIPT_DIR/git-prune.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

rc=0
bash "$PRUNE" --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

git init "$TEST_TMPDIR/repo" >/dev/null 2>&1
out="$(GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" bash -c "cd '$TEST_TMPDIR/repo' && bash '$PRUNE'")"
assert_contains "dry-run lists worktree prune" "$out" "Planned: git worktree prune"
assert_contains "dry-run lists gc" "$out" "Planned: git gc --auto --quiet"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: git-prune.sh tests passed"
