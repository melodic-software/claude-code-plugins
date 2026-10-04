#!/usr/bin/env bash
# Self-contained contract tests for added-lines.sh (runs against throwaway git
# repos under mktemp; never touches the enclosing repository).
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/added-lines.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0
SKIPPED=0
TAB=$'\t'

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
skip() {
  SKIPPED=$((SKIPPED + 1))
  printf 'SKIP (host: %s): %s\n' "$2" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_equal() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email 'added-lines-test@example.invalid'
  git -C "$1" config user.name 'added-lines-test'
}
commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm "$2"
}

# --- Usage contract -------------------------------------------------------------

REPO="$TEST_TMPDIR/usage"
make_repo "$REPO"
printf 'a\n' >"$REPO/a.txt"
commit_all "$REPO" base

rc=0
(cd "$REPO" && bash "$SCRIPT" >/dev/null 2>&1) || rc=$?
assert_exit "no base argument exits 2" 2 "$rc"

rc=0
(cd "$REPO" && bash "$SCRIPT" no-such-ref >/dev/null 2>&1) || rc=$?
assert_exit "an unknown base exits 2" 2 "$rc"

rc=0
(cd "$REPO" && bash "$SCRIPT" --output=/dev/null >/dev/null 2>&1) || rc=$?
assert_exit "a base that starts with a dash exits 2" 2 "$rc"

rc=0
(cd "$TEST_TMPDIR" && bash "$SCRIPT" HEAD >/dev/null 2>&1) || rc=$?
assert_exit "outside a repository exits 2" 2 "$rc"

# --- Hunks: start, count, path last -----------------------------------------------

REPO="$TEST_TMPDIR/hunks"
make_repo "$REPO"
printf '%s\n' one two three four five six seven eight >"$REPO/app.py"
printf 'keep\n' >"$REPO/gone.py"
commit_all "$REPO" base
base="$(git -C "$REPO" rev-parse HEAD)"
# Insert two lines after line 1 and replace line 8; delete gone.py entirely.
printf '%s\n' one new-a new-b two three four five six seven EIGHT >"$REPO/app.py"
rm "$REPO/gone.py"
commit_all "$REPO" change

out="$(cd "$REPO" && bash "$SCRIPT" "$base")"
expected="2${TAB}2${TAB}app.py"$'\n'"10${TAB}1${TAB}app.py"
assert_equal "one row per added hunk, start then count then path" "$expected" "$out"

# Uncommitted edits count too: the diff is the working tree against the base. The
# appended line 11 sits next to the committed line 10, so the two form one hunk.
printf 'tail\n' >>"$REPO/app.py"
out="$(cd "$REPO" && bash "$SCRIPT" "$base")"
assert_equal "an uncommitted added line is reported" "10${TAB}2${TAB}app.py" "$(tail -n 1 <<<"$out")"

# A base whose history moved on is read from the merge base, so lines added on the
# base side never appear as this branch's additions.
REPO="$TEST_TMPDIR/mergebase"
make_repo "$REPO"
printf 'shared\n' >"$REPO/s.py"
commit_all "$REPO" base
git -C "$REPO" branch -q basebranch
printf 'shared\nmine\n' >"$REPO/s.py"
commit_all "$REPO" mine
git -C "$REPO" checkout -q basebranch
printf 'theirs\n' >"$REPO/t.py"
commit_all "$REPO" theirs
git -C "$REPO" checkout -q -
out="$(cd "$REPO" && bash "$SCRIPT" basebranch)"
assert_equal "only the branch's own additions, read from the merge base" "2${TAB}1${TAB}s.py" "$out"

# --- Path forms -----------------------------------------------------------------

REPO="$TEST_TMPDIR/spaces"
make_repo "$REPO"
printf 'x\n' >"$REPO/seed.txt"
commit_all "$REPO" base
base="$(git -C "$REPO" rev-parse HEAD)"
mkdir -p "$REPO/sub dir"
printf 'a\nb\n' >"$REPO/sub dir/my file.py"
commit_all "$REPO" add
out="$(cd "$REPO" && bash "$SCRIPT" "$base")"
assert_equal "a file name with a space survives whole" "1${TAB}2${TAB}sub dir/my file.py" "$out"

# A rename with one edited line reports the edit under the new path, not the whole file.
REPO="$TEST_TMPDIR/rename"
make_repo "$REPO"
printf '%s\n' l1 l2 l3 l4 l5 l6 l7 l8 l9 l10 >"$REPO/old.py"
commit_all "$REPO" base
base="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" mv old.py new.py
printf '%s\n' l1 l2 l3 l4 l5 l6 l7 l8 l9 l10 l11 >"$REPO/new.py"
commit_all "$REPO" rename
out="$(cd "$REPO" && bash "$SCRIPT" "$base")"
assert_equal "a rename reports only its added lines, under the new path" "11${TAB}1${TAB}new.py" "$out"

# A path carrying a control character cannot be printed unambiguously, so the run fails.
REPO="$TEST_TMPDIR/control"
make_repo "$REPO"
printf 'x\n' >"$REPO/seed.txt"
commit_all "$REPO" base
base="$(git -C "$REPO" rev-parse HEAD)"
bad=$'bad\tname.py'
if : >"$REPO/$bad" 2>/dev/null && [[ -f "$REPO/$bad" ]]; then
  printf 'y\n' >"$REPO/$bad"
  commit_all "$REPO" add
  rc=0
  out="$(cd "$REPO" && bash "$SCRIPT" "$base" 2>/dev/null)" || rc=$?
  assert_exit "a path with a control character exits 2" 2 "$rc"
  assert_equal "a refused run prints no rows" "" "$out"
else
  skip "a path with a control character exits 2" "cannot create a file name holding a tab"
fi

# --- A configured external diff never reaches the parser ---------------------------
# diff.external set to a driver that prints the new file verbatim: the file's text is a
# crafted hunk header whose count is an array subscript holding a command. Parsing it as
# arithmetic would create the marker file. The run must exit 0 or 2 and never execute it.

REPO="$TEST_TMPDIR/extdiff"
make_repo "$REPO"
printf 'x\n' >"$REPO/seed.txt"
commit_all "$REPO" base
base="$(git -C "$REPO" rev-parse HEAD)"
MARK="$TEST_TMPDIR/PWNED"
EXT="$TEST_TMPDIR/ext-diff.sh"
# shellcheck disable=SC2016 # the driver's "$5" is meant for the driver, not this shell
printf '%s\n' '#!/usr/bin/env bash' 'cat "$5"' >"$EXT"
chmod +x "$EXT"
git -C "$REPO" config diff.external "$EXT"
# shellcheck disable=SC2016 # the command substitution is the attack text, written literally
printf '@@ -1 +1,BASH_VERSINFO[$(touch %s)] @@\n' "$MARK" >"$REPO/evil.txt"
commit_all "$REPO" crafted

DETECT="$SCRIPT_DIR/../skills/audit-comment-residue/scripts/detect.sh"
for compat in default 51; do
  for runner in added-lines detect; do
    rm -f "$MARK"
    if [[ "$runner" == added-lines ]]; then
      cmd=(bash "$SCRIPT" "$base")
    else
      cmd=(bash "$DETECT" --added-since "$base")
    fi
    rc=0
    if [[ "$compat" == default ]]; then
      (cd "$REPO" && "${cmd[@]}" >/dev/null 2>&1) || rc=$?
    else
      (cd "$REPO" && BASH_COMPAT=51 "${cmd[@]}" >/dev/null 2>&1) || rc=$?
    fi
    if [[ -e "$MARK" ]]; then
      fail "$runner under bash compat $compat ignores diff.external" "no marker file" "marker created"
    elif [[ "$rc" == 0 || "$rc" == 2 ]]; then
      pass "$runner under bash compat $compat ignores diff.external"
    else
      fail "$runner under bash compat $compat ignores diff.external" "exit 0 or 2" "exit $rc"
    fi
  done
done

# The external driver is ignored, so the crafted file reads as one ordinary added line.
out="$(cd "$REPO" && bash "$SCRIPT" "$base")"
assert_equal "with diff.external set, rows come from git's own diff" "1${TAB}1${TAB}evil.txt" "$out"

# --- Final report ---------------------------------------------------------------

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed, %d host skip(s).\n' "$CASE_NUM" "$SKIPPED"
  exit 0
fi
printf '\n%d/%d checks failed, %d host skip(s).\n' "$FAILED" "$CASE_NUM" "$SKIPPED" >&2
exit 1
