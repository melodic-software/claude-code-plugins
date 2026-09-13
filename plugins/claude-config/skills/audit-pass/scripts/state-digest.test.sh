#!/usr/bin/env bash
# Regression tests for state-digest.sh (self-contained — ships with the plugin).
#
# The load-bearing tests here re-derive the digest INDEPENDENTLY, by printing the
# pinned body with printf and hashing it, rather than comparing the script
# against itself. A test that only asserted "the same input gives the same
# output" would pass under any ordering, any separator, and any hash, which is
# exactly the underspecification this script exists to close.
#
# Two are NEGATIVE tests in the sense this repo means it: they mutate a copy of
# the script to delete exactly one check and assert the mutated copy reaches the
# outcome the real one refuses.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` into the caller's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/state-digest.sh"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected: $2, actual: $3"; fi
}
assert_ne() {
  if [[ "$2" != "$3" ]]; then pass "$1"; else fail "$1" "expected a difference, both were: $2"; fi
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
  *"$3"*) fail "$1" "expected NOT to contain: $3" ;;
  *) pass "$1" ;;
  esac
}

run() { bash "$SCRIPT" "$@"; }

# An independent sha256 of stdin, so the expected values below are not produced
# by the code under test.
ref_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    shasum -a 256 | cut -d' ' -f1
  fi
}

FIX="$TEST_TMPDIR/fix"
mkdir -p "$FIX"
printf 'alpha\n' >"$FIX/a.md"
printf 'beta\n' >"$FIX/b.md"

HA=$(ref_sha <"$FIX/a.md")
HB=$(ref_sha <"$FIX/b.md")

LIST="$TEST_TMPDIR/list.tsv"
printf 'b.md\t%s\na.md\t%s\n' "$FIX/b.md" "$FIX/a.md" >"$LIST"

# --- Case 1: the digest matches an independent re-derivation ----------------
#
# Sorted ascending by byte order, `surface 0x1F hash`, entries joined by 0x1E,
# no trailing separator, sha256 of the whole body. The list above is in the
# OTHER order deliberately, so a script that hashed input order would fail here.

EXPECTED=$(printf 'a.md\x1f%s\x1eb.md\x1f%s' "$HA" "$HB" | ref_sha)
ACTUAL=$(run digest --list "$LIST")
assert_eq "the digest equals the independently derived pinned body" "$EXPECTED" "$ACTUAL"
assert_eq "the digest is 64 lowercase hex characters" 64 "${#ACTUAL}"

# --- Case 2: deduplication on the surface token -----------------------------

DUPES="$TEST_TMPDIR/dupes.tsv"
printf 'a.md\t%s\nb.md\t%s\na.md\t%s\n' "$FIX/a.md" "$FIX/b.md" "$FIX/a.md" >"$DUPES"
assert_eq "a surface listed twice contributes exactly one entry" \
  "$EXPECTED" "$(run digest --list "$DUPES")"

# --- Case 3: the two sentinels ----------------------------------------------

MISSING="$TEST_TMPDIR/missing.tsv"
printf 'gone.md\t%s\n' "$FIX/does-not-exist" >"$MISSING"
EXPECTED_MISSING=$(printf 'gone.md\x1fdeleted' | ref_sha)
assert_eq "a path that does not exist pairs with the deleted sentinel" \
  "$EXPECTED_MISSING" "$(run digest --list "$MISSING")"
assert_eq "hash-file reports the deleted sentinel directly" \
  "deleted" "$(run hash-file --path "$FIX/does-not-exist")"

mkdir -p "$FIX/adir"
assert_eq "a path that cannot be read as bytes pairs with the unreadable sentinel" \
  "unreadable" "$(run hash-file --path "$FIX/adir")"

# Neither sentinel can be mistaken for a content hash, which is the property that
# lets one field carry both.
for sentinel in deleted unreadable; do
  if [[ "$sentinel" =~ ^[0-9a-f]{64}$ ]]; then
    fail "the $sentinel sentinel is distinguishable from a content hash" "it is 64 hex chars"
  else
    pass "the $sentinel sentinel is distinguishable from a content hash"
  fi
done

# --- Case 4: the empty entry set --------------------------------------------

EMPTY_EXPECTED=$(printf '' | ref_sha)
assert_eq "a digest over no entries is sha256 of the empty byte string" \
  "$EMPTY_EXPECTED" "$(printf '' | run digest --list -)"

# --- Case 5: --exclude removes an entry before hashing ----------------------

EXPECTED_A_ONLY=$(printf 'a.md\x1f%s' "$HA" | ref_sha)
assert_eq "--exclude drops that surface from the body" \
  "$EXPECTED_A_ONLY" "$(run digest --list "$LIST" --exclude b.md)"

# --- Case 6: input-digest sorts cfg entries IN, not after -------------------
#
# `cfg:harness-version` sorts after `a.md` and `b.md` by byte order; a token that
# sorts BEFORE them proves the cfg entries are not simply appended.

HV=$(printf '2.1.268' | ref_sha)
EXPECTED_CFG=$(printf 'a.md\x1f%s\x1eb.md\x1f%s\x1ecfg:harness-version\x1f%s' "$HA" "$HB" "$HV" | ref_sha)
assert_eq "input-digest hashes cfg entries on the same terms as file entries" \
  "$EXPECTED_CFG" "$(run input-digest --list "$LIST" --config 'cfg:harness-version=2.1.268')"

CFG_LIST="$TEST_TMPDIR/zlist.tsv"
printf 'zz.md\t%s\n' "$FIX/a.md" >"$CFG_LIST"
EXPECTED_SORTED_IN=$(printf 'cfg:x\x1f%s\x1ezz.md\x1f%s' "$(printf '1' | ref_sha)" "$HA" | ref_sha)
assert_eq "a cfg entry sorting before a file entry lands before it in the body" \
  "$EXPECTED_SORTED_IN" "$(run input-digest --list "$CFG_LIST" --config 'cfg:x=1')"

rc=0
run input-digest --list "$LIST" --config 'harness=2.1.268' >/dev/null 2>&1 || rc=$?
assert_exit "a --config token not prefixed cfg: is refused" 2 "$rc"

# --- Case 7: content changes move the digest --------------------------------

printf 'beta changed\n' >"$FIX/b.md"
assert_ne "editing a file's contents changes the digest" \
  "$EXPECTED" "$(run digest --list "$LIST")"
printf 'beta\n' >"$FIX/b.md"

# --- Case 8: dirty, and the --untracked-files=all requirement ---------------

REPO="$TEST_TMPDIR/repo"
mkdir -p "$REPO/nested"
git -C "$REPO" init --quiet >/dev/null 2>&1
printf 'x\n' >"$REPO/nested/untracked.md"

DIRTY=$(run dirty --target "$REPO")
assert_contains "dirty lists a file inside an untracked directory" "$DIRTY" "nested/untracked.md"
assert_contains "dirty emits <surface>TAB<path> entries the digest can consume" \
  "$DIRTY" "nested/untracked.md	$REPO/nested/untracked.md"

# NEGATIVE: drop --untracked-files=all and the untracked directory collapses to
# one `?? nested/` entry, which is a directory and hashes to a sentinel rather
# than to the file's content. A bound whose removal changes nothing is not a bound.
COPY="$TEST_TMPDIR/no-untracked-all.sh"
sed 's/--untracked-files=all //' "$SCRIPT" >"$COPY"
MUTATED=$(bash "$COPY" dirty --target "$REPO")
assert_not_contains "without --untracked-files=all the file inside it is not listed" \
  "$MUTATED" "nested/untracked.md"

# NEGATIVE: remove the LC_ALL=C pin and the sort inherits the caller's collation.
# Under a locale that ignores punctuation, `a-b.md` and `ab.md` swap places
# against byte order, so the digest moves. Where no such locale is installed the
# two agree and the case reports as not discriminating rather than as a pass.
printf 'one\n' >"$FIX/a-b.md"
printf 'two\n' >"$FIX/ab.md"
COLLATE="$TEST_TMPDIR/collate.tsv"
printf 'ab.md\t%s\na-b.md\t%s\n' "$FIX/ab.md" "$FIX/a-b.md" >"$COLLATE"
HAB=$(ref_sha <"$FIX/ab.md")
HA_B=$(ref_sha <"$FIX/a-b.md")
# Byte order: '-' (0x2D) < 'b' (0x62), so `a-b.md` precedes `ab.md`.
EXPECTED_BYTE=$(printf 'a-b.md\x1f%s\x1eab.md\x1f%s' "$HA_B" "$HAB" | ref_sha)
assert_eq "entries sort by byte order, not by locale collation" \
  "$EXPECTED_BYTE" "$(run digest --list "$COLLATE")"

UNPINNED="$TEST_TMPDIR/unpinned-sort.sh"
sed 's/LC_ALL=C sort/sort/' "$SCRIPT" >"$UNPINNED"
LOCALE_NAME=""
for cand in en_US.UTF-8 en_US.utf8 C.UTF-8; do
  if locale -a 2>/dev/null | grep -qxF "$cand"; then
    LOCALE_NAME="$cand"
    break
  fi
done
if [[ -z "$LOCALE_NAME" ]]; then
  printf 'SKIP: no punctuation-ignoring locale installed, the LC_ALL=C pin is not discriminated here\n'
else
  UNPINNED_OUT=$(LC_ALL="$LOCALE_NAME" bash "$UNPINNED" digest --list "$COLLATE")
  PINNED_OUT=$(LC_ALL="$LOCALE_NAME" run digest --list "$COLLATE")
  assert_eq "the pinned sort is locale-proof" "$EXPECTED_BYTE" "$PINNED_OUT"
  if [[ "$UNPINNED_OUT" == "$EXPECTED_BYTE" ]]; then
    printf 'SKIP: locale %s collates identically to byte order here, the pin is not discriminated\n' "$LOCALE_NAME"
  else
    pass "removing LC_ALL=C changes the digest under $LOCALE_NAME"
  fi
fi

# --- Case 9: usage ----------------------------------------------------------

rc=0
run >/dev/null 2>&1 || rc=$?
assert_exit "no command exits 2" 2 "$rc"
rc=0
run nonsense >/dev/null 2>&1 || rc=$?
assert_exit "an unknown command exits 2" 2 "$rc"
rc=0
run digest >/dev/null 2>&1 || rc=$?
assert_exit "digest without --list exits 2" 2 "$rc"
rc=0
run digest --list "$TEST_TMPDIR/nope.tsv" >/dev/null 2>&1 || rc=$?
assert_exit "an unreadable --list exits 2" 2 "$rc"
rc=0
BAD="$TEST_TMPDIR/bad.tsv"
printf 'no-tab-here\n' >"$BAD"
run digest --list "$BAD" >/dev/null 2>&1 || rc=$?
assert_exit "a list entry with no tab exits 2" 2 "$rc"
rc=0
run --help >/dev/null 2>&1 || rc=$?
assert_exit "--help exits 0" 0 "$rc"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
