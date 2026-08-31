#!/usr/bin/env bash
# Self-contained contract tests for changed-code-files.sh (runs against throwaway
# git repos under mktemp; never touches the enclosing repository).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/changed-code-files.sh"
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
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_absent() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q >/dev/null 2>&1
  git -C "$1" config user.email 'changed-code-files-test@example.invalid' >/dev/null 2>&1
  git -C "$1" config user.name 'changed-code-files-test' >/dev/null 2>&1
}

# --- 1. Mixed working tree: code listed, non-code and rename origin excluded ----

REPO="$TEST_TMPDIR/repo"
make_repo "$REPO"
printf 'base\n' >"$REPO/committed.ts"
printf 'base\n' >"$REPO/old.go"
printf 'base\n' >"$REPO/notes.txt"
git -C "$REPO" add -A >/dev/null 2>&1
git -C "$REPO" commit -qm base >/dev/null 2>&1

printf 'changed\n' >>"$REPO/committed.ts"
printf 'new\n' >"$REPO/untracked.py"
printf 'changed\n' >>"$REPO/notes.txt"
git -C "$REPO" mv old.go new.go >/dev/null 2>&1

out=$(cd "$REPO" && bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "mixed tree exits 0" 0 "$rc"
assert_contains "modified code file listed" "$out" "committed.ts"
assert_contains "untracked code file listed" "$out" "untracked.py"
assert_contains "rename lists destination" "$out" "new.go"
assert_absent "rename origin excluded" "$out" "old.go"
assert_absent "non-code file excluded" "$out" "notes.txt"

# --- 2. Cap applies ------------------------------------------------------------

out=$(cd "$REPO" && bash "$SCRIPT" 1 2>&1)
rc=$?
line_count=$(printf '%s\n' "$out" | grep -c .)
assert_exit "capped run exits 0" 0 "$rc"
assert_exit "cap of 1 emits 1 line" 1 "$line_count"

# --- 3. Clean tree emits nothing ------------------------------------------------

CLEAN="$TEST_TMPDIR/clean"
make_repo "$CLEAN"
printf 'base\n' >"$CLEAN/a.ts"
git -C "$CLEAN" add -A >/dev/null 2>&1
git -C "$CLEAN" commit -qm base >/dev/null 2>&1
out=$(cd "$CLEAN" && bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "clean tree exits 0" 0 "$rc"
assert_exit "clean tree emits nothing" 0 "${#out}"

# --- 4. Outside a repo exits 1 (caller supplies fallback text) -------------------

NOREPO="$TEST_TMPDIR/norepo"
mkdir -p "$NOREPO"
out=$(cd "$NOREPO" && GIT_CEILING_DIRECTORIES="$TEST_TMPDIR" bash "$SCRIPT" 2>&1)
rc=$?
assert_exit "outside a repo exits 1" 1 "$rc"

# --- Final report ---------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
