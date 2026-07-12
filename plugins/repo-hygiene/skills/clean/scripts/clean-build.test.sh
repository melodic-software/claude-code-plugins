#!/usr/bin/env bash
# Tests for clean-build.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

BUILD="$SCRIPT_DIR/clean-build.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT
FAILED=0

git init "$TEST_TMPDIR/repo" >/dev/null 2>&1
git -C "$TEST_TMPDIR/repo" config user.email "t@example.com"
git -C "$TEST_TMPDIR/repo" config user.name "Test"
mkdir -p "$TEST_TMPDIR/repo/apps/foo/bin"
echo dll >"$TEST_TMPDIR/repo/apps/foo/bin/x.dll"

run_build() {
  GIT_DIR="$TEST_TMPDIR/repo/.git" GIT_WORK_TREE="$TEST_TMPDIR/repo" \
    bash -c "cd '$TEST_TMPDIR/repo' && bash '$BUILD' $*"
}

out="$(run_build)"
assert_contains "dry-run plans bin" "$out" "Planned remove:"
assert_file_exists "dry-run keeps bin" "$TEST_TMPDIR/repo/apps/foo/bin/x.dll"

out="$(run_build --apply)"
assert_contains "apply removes bin" "$out" "Removed:"
assert_file_absent "bin removed" "$TEST_TMPDIR/repo/apps/foo/bin/x.dll"

# A build-output dir holding a protected descendant is preserved whole, not
# rm -rf'd out from under the secret nested inside it.
mkdir -p "$TEST_TMPDIR/repo/dist"
echo secret >"$TEST_TMPDIR/repo/dist/.env"
echo art >"$TEST_TMPDIR/repo/dist/bundle.js"
out="$(run_build --apply)"
assert_contains "protected-descendant dir skipped" "$out" "Skip (protected descendant):"
assert_file_exists "nested .env preserved" "$TEST_TMPDIR/repo/dist/.env"

# A build-output dir living inside a submodule is preserved — its files are
# tracked by the submodule, not the superproject index.
printf '[submodule "sub"]\n\tpath = deps/sub\n\turl = ./sub\n' >"$TEST_TMPDIR/repo/.gitmodules"
mkdir -p "$TEST_TMPDIR/repo/deps/sub/build"
echo compiled >"$TEST_TMPDIR/repo/deps/sub/build/app.js"
out="$(run_build --apply)"
assert_contains "submodule build dir skipped" "$out" "Skip (submodule):"
assert_file_exists "submodule tracked file preserved" "$TEST_TMPDIR/repo/deps/sub/build/app.js"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: clean-build.sh tests passed"
