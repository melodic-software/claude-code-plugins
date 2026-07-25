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

# --- manifest / nested-dedup / apply-from-manifest / resume ---
# Fresh repo so progressive mutation above does not bleed into these cases.
git init "$TEST_TMPDIR/b2" >/dev/null 2>&1
git -C "$TEST_TMPDIR/b2" config user.email "t@example.com"
git -C "$TEST_TMPDIR/b2" config user.name "Test"
# bin/ with a nested obj/ — both are build dir names; the walk returns both but
# the ancestor (bin/) must collapse the descendant so the byte total is not
# double-counted and apply does not chase an already-removed path.
mkdir -p "$TEST_TMPDIR/b2/bin/obj"
echo a >"$TEST_TMPDIR/b2/bin/x.dll"
echo b >"$TEST_TMPDIR/b2/bin/obj/y.dll"
# A caches-tier target too, to prove --include-caches folds both classes into
# the one build manifest (no clean-caches.sh subprocess).
mkdir -p "$TEST_TMPDIR/b2/.pytest_cache"
echo c >"$TEST_TMPDIR/b2/.pytest_cache/c"
MANI="$TEST_TMPDIR/b2.manifest"

run_b2() {
  bash -c "cd '$TEST_TMPDIR/b2' && bash '$BUILD' $*"
}

out="$(run_b2 --dry-run --include-caches --manifest "$MANI")"
assert_contains "dry-run prints manifest path" "$out" "Manifest: $MANI"
# bin/ (nested obj/ deduped) + .pytest_cache = 2 planned.
assert_contains "nested dir deduped, caches folded in" "$out" "Summary: planned=2 bytes="
mani_body="$(cat "$MANI")"
# Structural pin (the manifest is a consumed contract): exact class<TAB>bytes<TAB>path per tier.
if grep -qE "^build"$'\t'"[0-9]+"$'\t'"bin$" "$MANI"; then
  pass "build line is class<TAB>bytes<TAB>path"
else
  fail "build manifest line format" "build<TAB><int><TAB>bin" "$mani_body"
fi
if grep -qE "^caches"$'\t'"[0-9]+"$'\t'"\.pytest_cache$" "$MANI"; then
  pass "caches line folded into build manifest"
else
  fail "folded caches manifest line" "caches<TAB><int><TAB>.pytest_cache" "$mani_body"
fi
assert_not_contains "nested obj not a separate entry" "$mani_body" "bin/obj"
assert_file_exists "dry-run does not mutate" "$TEST_TMPDIR/b2/bin/obj/y.dll"

out="$(run_b2 --apply --manifest "$MANI")"
rc=$?
assert_contains "apply-from-manifest removes bin" "$out" "Removed: bin"
assert_contains "apply summary shape" "$out" "Summary: removed=2 failed=0 bytes="
assert_exit "apply exit 0" 0 "$rc"
assert_file_absent "bin gone after apply" "$TEST_TMPDIR/b2/bin/x.dll"
assert_file_absent "folded cache gone after apply" "$TEST_TMPDIR/b2/.pytest_cache/c"

out="$(run_b2 --apply --manifest "$MANI")"
rc=$?
assert_contains "resume removes nothing" "$out" "Summary: removed=0 failed=0 bytes=0"
assert_exit "resume exit 0" 0 "$rc"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: clean-build.sh tests passed"
