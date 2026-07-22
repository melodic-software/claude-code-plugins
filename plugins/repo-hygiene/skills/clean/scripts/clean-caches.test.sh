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

# 3. Target validation — an entry naming an ordinary untracked dir that is not a
#    cache target (here `notes/`) is rejected by the tier's candidate rules, never
#    removed, and counts as a failure. Without this, a tampered manifest could
#    delete any unprotected untracked path.
mkdir -p "$TEST_TMPDIR/r2/notes"
echo n >"$TEST_TMPDIR/r2/notes/keep"
printf 'caches\t1\tnotes\n' >"$TEST_TMPDIR/r2.bogus.manifest"
out="$(run_r2 --apply --manifest "$TEST_TMPDIR/r2.bogus.manifest" 2>&1)"
rc=$?
assert_contains "non-target entry rejected" "$out" "Rejected (not a caches target): notes"
assert_exit "non-target apply exits non-zero" 1 "$rc"
assert_file_exists "unrelated untracked dir preserved" "$TEST_TMPDIR/r2/notes/keep"

# Wrong-tier entry (a build-class line handed to the caches tier) is rejected too.
printf 'build\t1\tbin\n' >"$TEST_TMPDIR/r2.wrongtier.manifest"
mkdir -p "$TEST_TMPDIR/r2/bin"
echo b >"$TEST_TMPDIR/r2/bin/x"
out="$(run_r2 --apply --manifest "$TEST_TMPDIR/r2.wrongtier.manifest" 2>&1)"
rc=$?
assert_contains "wrong-tier entry rejected" "$out" "Rejected (wrong tier): bin"
assert_file_exists "wrong-tier target preserved" "$TEST_TMPDIR/r2/bin/x"

# 4. Type validation — a regular file whose basename matches a dir-name target
#    (enumeration only emits those under -type d) is rejected, never removed.
mkdir -p "$TEST_TMPDIR/r2/src"
echo f >"$TEST_TMPDIR/r2/src/__pycache__" # a FILE named like a cache dir
printf 'caches\t1\tsrc/__pycache__\n' >"$TEST_TMPDIR/r2.type.manifest"
out="$(run_r2 --apply --manifest "$TEST_TMPDIR/r2.type.manifest" 2>&1)"
rc=$?
assert_contains "file-as-dir target rejected" "$out" "Rejected (not a caches target): src/__pycache__"
assert_exit "type-mismatch apply exits non-zero" 1 "$rc"
assert_file_exists "misnamed file preserved" "$TEST_TMPDIR/r2/src/__pycache__"

# 5. Fail closed on an unreadable/missing manifest — silently doing nothing and
#    exiting 0 would let automation treat a mistyped path as a successful sweep.
out="$(run_r2 --apply --manifest "$TEST_TMPDIR/does-not-exist.manifest" 2>&1)"
rc=$?
assert_contains "missing manifest reported" "$out" "manifest not readable"
assert_exit "missing manifest exits non-zero" 1 "$rc"

# 6. Dry-run must not truncate an arbitrary --manifest destination: an existing
#    non-manifest file (a mistyped path) is refused, not erased.
printf 'important user config\n' >"$TEST_TMPDIR/precious.conf"
out="$(run_r2 --dry-run --manifest "$TEST_TMPDIR/precious.conf" 2>&1)"
rc=$?
assert_contains "non-manifest overwrite refused" "$out" "refusing to overwrite non-manifest file"
assert_exit "refuse-overwrite exits non-zero" 1 "$rc"
preserved="$(cat "$TEST_TMPDIR/precious.conf")"
assert_contains "precious file left intact" "$preserved" "important user config"
# Re-writing an existing MANIFEST-format file is still allowed (dry-run reuse).
out="$(run_r2 --dry-run --manifest "$MANI" 2>&1)"
rc=$?
assert_exit "rewriting a real manifest still works" 0 "$rc"

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
  # `.mypy_cache` is a valid explicit cache target; rm cannot empty it while the
  # dir stays write-denied, so this exercises the genuine Unremovable branch.
  printf 'caches\t4096\t.mypy_cache\n' >"$TEST_TMPDIR/r2.fail.manifest"
  out="$(run_r2 --apply --manifest "$TEST_TMPDIR/r2.fail.manifest" 2>&1)"
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
