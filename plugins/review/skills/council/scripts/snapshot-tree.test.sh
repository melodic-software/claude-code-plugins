#!/usr/bin/env bash
# Tests for snapshot-tree.sh in a throwaway repository and a linked worktree of it. Expected values
# come from git's own meaning of a tree id (same content, same id; any change, a different id) and
# the script's stated promise to change no ref, index or work-tree file.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/snapshot-tree.sh"
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
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_ne() { if [[ "$2" != "$3" ]]; then pass "$1"; else fail "$1" "not $2" "$3"; fi; }

g() { git -C "$1" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "${@:2}"; }
snap() { (cd "$1" && bash "$SCRIPT"); }
index_sum() { cksum <"$(cd "$1" && git rev-parse --path-format=absolute --git-path index)"; }
# --no-optional-locks keeps status from refreshing the index, so only the script could change it.
state() { printf '%s\n--\n%s\n--\n%s\n' "$(index_sum "$1")" "$(g "$1" for-each-ref)" "$(g "$1" --no-optional-locks status --porcelain)"; }

MAIN="$TEST_TMPDIR/main"
mkdir -p "$MAIN"
g "$MAIN" init -q
printf 'one\n' >"$MAIN/a.txt"
printf 'ignored/\n' >"$MAIN/.gitignore"
g "$MAIN" add -A
g "$MAIN" commit -q -m base
g "$MAIN" worktree add -q "$TEST_TMPDIR/linked" -b side
LINKED="$TEST_TMPDIR/linked"

for where in main linked; do
  if [[ "$where" == main ]]; then R="$MAIN"; else R="$LINKED"; fi
  printf 'staged\n' >"$R/staged.txt"
  g "$R" add staged.txt
  before_state="$(state "$R")"

  s1="$(snap "$R")"
  assert_eq "$where: prints one tree id" "1" "$(printf '%s\n' "$s1" | grep -cE '^[0-9a-f]{40}([0-9a-f]{24})?$')"
  assert_eq "$where: two runs with no change give the same id" "$s1" "$(snap "$R")"
  assert_eq "$where: index, refs and status unchanged by the run" "$before_state" "$(state "$R")"

  printf 'two\n' >>"$R/a.txt"
  s2="$(snap "$R")"
  assert_ne "$where: an edit changes the id" "$s1" "$s2"

  printf 'new\n' >"$R/created.txt"
  s3="$(snap "$R")"
  assert_ne "$where: a created file changes the id" "$s2" "$s3"
  assert_eq "$where: the diff names the created file" "created.txt" "$(g "$R" diff --name-only "$s2" "$s3")"

  mkdir -p "$R/ignored"
  printf 'x\n' >"$R/ignored/x.txt"
  assert_eq "$where: an ignored file does not change the id" "$s3" "$(snap "$R")"
  assert_eq "$where: no throwaway index is left in the git directory" "0" "$(find "$(cd "$R" && git rev-parse --absolute-git-dir)" -maxdepth 1 -name 'council-snapshot-*' | wc -l | tr -d ' ')"
done

out="$(cd "$TEST_TMPDIR" && bash "$SCRIPT" 2>&1)"
assert_eq "outside a work tree: exits 1" "1" "$(cd "$TEST_TMPDIR" && bash "$SCRIPT" >/dev/null 2>&1; echo $?)"
assert_eq "outside a work tree: one stderr line" "1" "$(printf '%s\n' "$out" | grep -c .)"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
