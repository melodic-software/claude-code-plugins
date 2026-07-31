#!/usr/bin/env bash
# Regression tests for list-workspaces.sh (self-contained — ships with the plugin).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/list-workspaces.sh"

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
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3" ;;
  esac
}

# The slug the script must derive, computed here from the SKILL.md spec independently of
# the script, so a drifting implementation fails rather than agreeing with itself.
expected_slug() {
  local canonical basename_slug path_hash
  canonical="$(realpath "$1" 2>/dev/null || readlink -f "$1" 2>/dev/null || printf '%s' "$1")"
  basename_slug="$(basename "$canonical" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')"
  path_hash="$(printf '%s' "$canonical" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -c1-8)"
  printf '%s-%s' "$basename_slug" "$path_hash"
}

# --- Case 1: --help exits 0 with usage ---

rc=0
OUT=$(bash "$SCRIPT" --help) || rc=$?
assert_exit "--help exits 0" 0 "$rc"
assert_contains "--help prints usage" "$OUT" "Usage:"

# --- Case 2: wrong argument count is a usage error ---

rc=0
OUT=$(bash "$SCRIPT" only-one 2>/dev/null) || rc=$?
assert_exit "one argument exits 2" 2 "$rc"

# --- Build a fixture project + plugin-data tree ---

PROJ="$TEST_TMPDIR/proj/My_Repo"
DATA="$TEST_TMPDIR/data"
mkdir -p "$PROJ" "$DATA"
SLUG="$(expected_slug "$PROJ")"

# --- Case 3: no workspaces yet => `none`, exit 0 ---

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$DATA") || rc=$?
assert_exit "no-match exits 0" 0 "$rc"
assert_eq "no-match prints none" "none" "$OUT"

# --- Case 4: a plugin-data dir that does not exist at all => `none`, exit 0 ---

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$TEST_TMPDIR/absent") || rc=$?
assert_exit "absent data dir exits 0" 0 "$rc"
assert_eq "absent data dir prints none" "none" "$OUT"

# --- Case 5: slug-hash dir listing ---
# Slug is basename-lowercased-slugified + `-` + 8 hex; `My_Repo` exercises both the
# case fold and the non-alphanumeric replacement.

mkdir -p "$DATA/$SLUG/topic/rust-ownership" "$DATA/$SLUG/codebase/auth-flow"
# A workspace belonging to a DIFFERENT project must not leak into this project's listing.
mkdir -p "$DATA/other-project-deadbeef/topic/unrelated"

rc=0
OUT=$(bash "$SCRIPT" "$PROJ" "$DATA") || rc=$?
assert_exit "listing exits 0" 0 "$rc"
assert_contains "slug is basename-slugified + hash" "$SLUG" "my-repo-"
assert_contains "lists the topic workspace" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"
assert_contains "lists the codebase workspace" "$OUT" "$DATA/$SLUG/codebase/auth-flow/"
assert_eq "lists exactly the two workspaces" "2" "$(printf '%s\n' "$OUT" | grep -c .)"

# --- Case 6: symlinked project resolves to the same workspace as the real path ---
# Canonicalization happens BEFORE the slug is derived, so an alias basename cannot split
# the workspace. Skipped where the OS refuses real symlinks (Windows without developer
# mode: Git Bash silently copies instead of linking).

LINK="$TEST_TMPDIR/proj/aliased-name"
if ln -s "$PROJ" "$LINK" 2>/dev/null && [[ -L "$LINK" ]]; then
  rc=0
  OUT=$(bash "$SCRIPT" "$LINK" "$DATA") || rc=$?
  assert_exit "symlinked project exits 0" 0 "$rc"
  assert_eq "symlinked project resolves to the real path's slug" "$SLUG" "$(expected_slug "$LINK")"
  assert_contains "symlinked project lists the same workspaces" "$OUT" "$DATA/$SLUG/topic/rust-ownership/"
else
  printf 'SKIP: symlink cases (this OS/filesystem does not support real symlinks)\n'
fi

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
