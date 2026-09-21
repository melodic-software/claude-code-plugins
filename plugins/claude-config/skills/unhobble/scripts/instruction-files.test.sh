#!/usr/bin/env bash
# Self-contained tests for instruction-files.sh (skill-script shape, per
# docs/conventions/shell-test-helpers/README.md: per-plugin assertion
# primitives are duplicated on purpose, never shared across plugins).
#
# Every fixture is a throwaway git repository built under mktemp and torn down
# on exit. Nothing here reads or writes a real repository, and the script under
# test takes its root as an explicit argument, so a run from any directory
# touches only the fixtures.
set -uo pipefail

# Isolate the fixture repositories from any ambient git environment: `git -C`
# changes directory but does not override discovery, so an exported GIT_DIR
# would land these throwaway identities in the CALLER's .git/config.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/instruction-files.sh"
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
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}
assert_absent() {
  if [[ -e "$2" ]]; then fail "$1" "still present: $2"; else pass "$1"; fi
}
assert_file_is() {
  local got
  got="$(cat "$2" 2>/dev/null)"
  if [[ "$got" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$got]"; fi
}

if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed" >&2
  exit 0
fi

# Build a fixture repo holding one file per "<relative path>=<content>" pair,
# committed, and print its path.
make_repo() {
  local name="$1" dir pair rel
  shift
  dir="$TEST_TMPDIR/$name"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email "fixture@example.invalid"
  git -C "$dir" config user.name "Fixture"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.autocrlf false
  for pair in "$@"; do
    rel="${pair%%=*}"
    mkdir -p "$dir/$(dirname "$rel")"
    printf '%s\n' "${pair#*=}" >"$dir/$rel"
  done
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "fixture"
  printf '%s' "$dir"
}

# --- Case 1: the shim pattern -- CLAUDE.md is a pointer, AGENTS.md is the
# instructions. Both AGENTS.md names must go with it, or the "bare" baseline
# still loads the repository's whole instruction surface.
repo="$(make_repo shim \
  'CLAUDE.md=@AGENTS.md' \
  'AGENTS.md=root instructions' \
  '.claude/AGENTS.md=dot-claude instructions')"
base="$(git -C "$repo" rev-parse HEAD)"

out="$("$SCRIPT" list "$repo")"
assert_equals "shim: list names both AGENTS.md files with the shim" \
  "$out" "CLAUDE.md
AGENTS.md
.claude/AGENTS.md"

out="$("$SCRIPT" strip "$repo" --all)"
assert_equals "shim: strip reports every instruction file it moved" \
  "$out" "CLAUDE.md
AGENTS.md
.claude/AGENTS.md"
assert_absent "shim: root AGENTS.md is gone after the strip" "$repo/AGENTS.md"
assert_absent "shim: .claude/AGENTS.md is gone after the strip" "$repo/.claude/AGENTS.md"
assert_absent "shim: CLAUDE.md is gone after the strip" "$repo/CLAUDE.md"
assert_equals "shim: nothing is left for list to find" "$("$SCRIPT" list "$repo")" ""

git -C "$repo" commit --quiet -m "strip"

# The phase-4 shape: the ledger defended ONE file, so only that one comes back.
# A restore that returned the whole pre-strip set would hand back instructions
# the ledger never defended and undo the experiment's result.
out="$("$SCRIPT" restore "$repo" "$base" AGENTS.md)"
assert_equals "shim: a named restore reports only the file it was asked for" \
  "$out" "AGENTS.md"
assert_file_is "shim: the named file is restored byte for byte" \
  "$repo/AGENTS.md" "root instructions"
assert_absent "shim: an unnamed file stays stripped" "$repo/.claude/AGENTS.md"
assert_absent "shim: the other unnamed file stays stripped" "$repo/CLAUDE.md"

# --all abandons the experiment: the pre-strip state entire, including the name
# already back on disk, which it checks out again rather than skipping.
out="$("$SCRIPT" restore "$repo" "$base" --all)"
assert_equals "shim: --all reports every name the ref has" \
  "$out" "CLAUDE.md
AGENTS.md
.claude/AGENTS.md"
assert_file_is "shim: .claude/AGENTS.md is restored byte for byte" \
  "$repo/.claude/AGENTS.md" "dot-claude instructions"
assert_file_is "shim: CLAUDE.md is restored byte for byte" \
  "$repo/CLAUDE.md" "@AGENTS.md"

out="$("$SCRIPT" restore "$repo" "$base" notes.md 2>&1)"
rc=$?
assert_equals "shim: a name off the list exits 2" "$rc" "2"
case "$out" in
*notes.md*) pass "shim: the message names the rejected argument" ;;
*) fail "shim: the message names the rejected argument" "got [$out]" ;;
esac

# A named restore of a file already on disk is an error, not a silent skip: the
# caller would otherwise record it as restored from the ref when it was not.
out="$("$SCRIPT" restore "$repo" "$base" AGENTS.md 2>&1)"
rc=$?
assert_equals "shim: restoring a file already present exits 2" "$rc" "2"

# --- Case 5b: a named restore whose source the ref does not have, and a ref
# that is not a commit. Both are errors. Exit 0 with nothing restored would let
# the caller's ledger claim a file came back while it stayed deleted.
repo="$(make_repo nosource 'CLAUDE.md=@AGENTS.md' 'AGENTS.md=root instructions')"
base="$(git -C "$repo" rev-parse HEAD)"
"$SCRIPT" strip "$repo" --all >/dev/null
git -C "$repo" commit --quiet -m "strip"
out="$("$SCRIPT" restore "$repo" "$base" .claude/AGENTS.md 2>&1)"
rc=$?
assert_equals "nosource: a name absent from the ref exits 2" "$rc" "2"
case "$out" in
*.claude/AGENTS.md*) pass "nosource: the message names the file it cannot source" ;;
*) fail "nosource: the message names the file it cannot source" "got [$out]" ;;
esac
assert_absent "nosource: nothing was restored" "$repo/AGENTS.md"
out="$("$SCRIPT" restore "$repo" no-such-ref AGENTS.md 2>&1)"
rc=$?
assert_equals "nosource: an unresolvable ref exits 2" "$rc" "2"
assert_absent "nosource: an unresolvable ref restored nothing" "$repo/AGENTS.md"

# --- Case 5c: --all overwrites. A file the experiment recreated or rewrote is
# what abandoning discards, so skipping it would leave experimental content
# behind and not return the pre-strip state at all.
printf 'rewritten during the experiment\n' >"$repo/AGENTS.md"
out="$("$SCRIPT" restore "$repo" "$base" --all)"
assert_equals "overwrite: --all reports the file it took back" "$out" "CLAUDE.md
AGENTS.md"
assert_file_is "overwrite: the rewritten file is returned to its pre-strip content" \
  "$repo/AGENTS.md" "root instructions"

# --- Case 5d: --all REMOVES a name the ref never had. The pre-strip state did
# not have it, so an abandon that left it behind would end with an instruction
# file loading that the experiment itself introduced.
printf 'written during the experiment\n' >"$repo/.claude/CLAUDE.md" 2>/dev/null ||
  { mkdir -p "$repo/.claude" && printf 'written during the experiment\n' >"$repo/.claude/CLAUDE.md"; }
out="$("$SCRIPT" restore "$repo" "$base" --all)"
case "$out" in
*"removed .claude/CLAUDE.md"*) pass "abandon: --all reports the file it removed" ;;
*) fail "abandon: --all reports the file it removed" "got [$out]" ;;
esac
assert_absent "abandon: an untracked file the ref never had is removed" \
  "$repo/.claude/CLAUDE.md"

# The same holds for one the experiment COMMITTED: it is tracked, so it leaves
# the index too rather than lingering as a staged deletion the operator misses.
mkdir -p "$repo/.claude"
printf 'committed during the experiment\n' >"$repo/.claude/CLAUDE.md"
git -C "$repo" add .claude/CLAUDE.md
git -C "$repo" commit --quiet -m "experiment added an instruction file"
out="$("$SCRIPT" restore "$repo" "$base" --all)"
case "$out" in
*"removed .claude/CLAUDE.md"*) pass "abandon: a tracked addition is removed too" ;;
*) fail "abandon: a tracked addition is removed too" "got [$out]" ;;
esac
assert_absent "abandon: the tracked addition is off disk" "$repo/.claude/CLAUDE.md"
assert_equals "abandon: and out of the index" \
  "$(git -C "$repo" ls-files .claude/CLAUDE.md)" ""

# --- Case 5e: strip names what it strips. A plan that classifies AGENTS.md as
# convention and keeps it must not have it deleted by a strip of the CLAUDE.md
# beside it.
repo="$(make_repo selective 'CLAUDE.md=behavioral lines' 'AGENTS.md=team conventions')"
out="$("$SCRIPT" strip "$repo" CLAUDE.md)"
assert_equals "selective: strip reports only the file it was asked for" "$out" "CLAUDE.md"
assert_absent "selective: the named file is stripped" "$repo/CLAUDE.md"
assert_file_is "selective: the file the plan kept is untouched" \
  "$repo/AGENTS.md" "team conventions"
out="$("$SCRIPT" strip "$repo" notes.md 2>&1)"
rc=$?
assert_equals "selective: a name off the list exits 2" "$rc" "2"
assert_file_is "selective: and strips nothing" "$repo/AGENTS.md" "team conventions"

# --- Case 2: a lone AGENTS.md, already read natively, with no CLAUDE.md at all.
repo="$(make_repo lone 'AGENTS.md=lone instructions' 'README.md=code')"
base="$(git -C "$repo" rev-parse HEAD)"
assert_equals "lone: list finds the AGENTS.md and nothing else" \
  "$("$SCRIPT" list "$repo")" "AGENTS.md"
"$SCRIPT" strip "$repo" --all >/dev/null
assert_absent "lone: AGENTS.md is stripped" "$repo/AGENTS.md"
git -C "$repo" commit --quiet -m "strip"
"$SCRIPT" restore "$repo" "$base" AGENTS.md >/dev/null
assert_file_is "lone: AGENTS.md comes back" "$repo/AGENTS.md" "lone instructions"

# --- Case 3: only .claude/AGENTS.md, whose parent directory the restore has to
# recreate because the strip removed the last file in it.
repo="$(make_repo dotclaude '.claude/AGENTS.md=dot-claude only')"
base="$(git -C "$repo" rev-parse HEAD)"
"$SCRIPT" strip "$repo" --all >/dev/null
assert_absent "dot-claude: the file is stripped" "$repo/.claude/AGENTS.md"
git -C "$repo" commit --quiet -m "strip"
"$SCRIPT" restore "$repo" "$base" .claude/AGENTS.md >/dev/null
assert_file_is "dot-claude: the file comes back with its directory" \
  "$repo/.claude/AGENTS.md" "dot-claude only"

# --- Case 4: a repository with no instruction files reports nothing and exits 0.
repo="$(make_repo bare 'README.md=code')"
out="$("$SCRIPT" list "$repo")"
rc=$?
assert_equals "bare: list prints nothing" "$out" ""
assert_equals "bare: list exits 0" "$rc" "0"
"$SCRIPT" strip "$repo" --all >/dev/null
assert_equals "bare: strip leaves the tree clean" "$(git -C "$repo" status --porcelain)" ""

# --- Case 6: an untracked instruction file stops the whole strip, with the tree
# untouched, rather than removing the files ahead of it and leaving the rest
# loaded.
repo="$(make_repo untracked 'CLAUDE.md=@AGENTS.md' 'AGENTS.md=root instructions')"
printf 'local only\n' >"$repo/CLAUDE.local.md"
out="$("$SCRIPT" strip "$repo" --all 2>&1)"
rc=$?
assert_equals "untracked: strip exits 2" "$rc" "2"
case "$out" in
*CLAUDE.local.md*) pass "untracked: the message names the untracked file" ;;
*) fail "untracked: the message names the untracked file" "got [$out]" ;;
esac
assert_file_is "untracked: AGENTS.md is untouched" "$repo/AGENTS.md" "root instructions"
assert_file_is "untracked: CLAUDE.md is untouched" "$repo/CLAUDE.md" "@AGENTS.md"

# --- Case 7: a TRACKED file with uncommitted edits. `git rm` without -f refuses
# it the same way it refuses an untracked one, so the pre-check has to catch it
# too. The dirty file is deliberately LAST in the name order, which is where an
# unchecked refusal would fire after the earlier names were already removed.
repo="$(make_repo dirty 'CLAUDE.md=@AGENTS.md' 'AGENTS.md=root instructions')"
printf 'edited in place\n' >"$repo/AGENTS.md"
out="$("$SCRIPT" strip "$repo" --all 2>&1)"
rc=$?
assert_equals "dirty: strip exits 2" "$rc" "2"
case "$out" in
*AGENTS.md*) pass "dirty: the message names the modified file" ;;
*) fail "dirty: the message names the modified file" "got [$out]" ;;
esac
assert_file_is "dirty: the earlier CLAUDE.md is NOT removed" "$repo/CLAUDE.md" "@AGENTS.md"
assert_file_is "dirty: the modified file is left as it was" "$repo/AGENTS.md" "edited in place"

# The staged-but-uncommitted form is the same refusal.
git -C "$repo" add AGENTS.md
out="$("$SCRIPT" strip "$repo" --all 2>&1)"
rc=$?
assert_equals "staged: strip exits 2" "$rc" "2"
assert_file_is "staged: the earlier CLAUDE.md is NOT removed" "$repo/CLAUDE.md" "@AGENTS.md"

# Once it is committed, the same strip goes through.
git -C "$repo" commit --quiet -m "edit"
out="$("$SCRIPT" strip "$repo" --all)"
assert_equals "committed: the strip now covers both files" \
  "$out" "CLAUDE.md
AGENTS.md"

# --- Case 5: the root is never inferred. A missing root is a usage error, not a
# run against the working directory.
"$SCRIPT" list >/dev/null 2>&1
assert_equals "usage: a missing root exits 2" "$?" "2"
"$SCRIPT" strip "$TEST_TMPDIR" >/dev/null 2>&1
assert_equals "usage: strip naming nothing exits 2" "$?" "2"
"$SCRIPT" strip "$TEST_TMPDIR" --all CLAUDE.md >/dev/null 2>&1
assert_equals "usage: strip --all mixed with a name exits 2" "$?" "2"
"$SCRIPT" restore "$TEST_TMPDIR" >/dev/null 2>&1
assert_equals "usage: restore without a ref exits 2" "$?" "2"
"$SCRIPT" restore "$TEST_TMPDIR" HEAD >/dev/null 2>&1
assert_equals "usage: restore naming nothing to restore exits 2" "$?" "2"
"$SCRIPT" restore "$TEST_TMPDIR" HEAD --all AGENTS.md >/dev/null 2>&1
assert_equals "usage: --all mixed with a name exits 2" "$?" "2"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]]
