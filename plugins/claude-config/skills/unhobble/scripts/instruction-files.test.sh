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

# --- Case 5a2: the target path is occupied by something that is not the file.
# `-f` is false for a directory and for a symlink to nowhere, and git checkout
# resolves the collision by DELETING the object, a nonempty directory included,
# so an emptier test than this one loses data the ref cannot restore.
repo="$(make_repo collide 'CLAUDE.md=original' '.claude/AGENTS.md=original dot')"
base="$(git -C "$repo" rev-parse HEAD)"
"$SCRIPT" strip "$repo" --all >/dev/null
git -C "$repo" commit --quiet -m "strip"

out="$("$SCRIPT" restore "$repo" "$base" CLAUDE.md 2>&1)"
assert_equals "collide: an unblocked name restores normally" "$out" "CLAUDE.md"

# A directory standing where the file goes.
rm -f "$repo/CLAUDE.md"
mkdir -p "$repo/CLAUDE.md"
printf 'keep me\n' >"$repo/CLAUDE.md/inner.txt"
out="$("$SCRIPT" restore "$repo" "$base" CLAUDE.md 2>&1)"
rc=$?
assert_equals "collide: a directory on the target exits 2" "$rc" "2"
assert_file_is "collide: the directory's contents survive" \
  "$repo/CLAUDE.md/inner.txt" "keep me"
rm -rf "$repo/CLAUDE.md"

# An ancestor that has become a regular file blocks .claude/AGENTS.md.
rm -rf "$repo/.claude"
printf 'a file where the directory goes\n' >"$repo/.claude"
out="$("$SCRIPT" restore "$repo" "$base" .claude/AGENTS.md 2>&1)"
rc=$?
assert_equals "collide: a non-directory ancestor exits 2" "$rc" "2"
assert_file_is "collide: the blocking ancestor survives" \
  "$repo/.claude" "a file where the directory goes"

# --all does not clobber it either: it reports and steps over.
out="$("$SCRIPT" restore "$repo" "$base" --all 2>&1)"
assert_file_is "collide: --all leaves the blocking ancestor alone" \
  "$repo/.claude" "a file where the directory goes"
case "$out" in
*"blocked by another object"*) pass "collide: --all reports what it stepped over" ;;
*) fail "collide: --all reports what it stepped over" "got [$out]" ;;
esac
rm -f "$repo/.claude"

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

# --- Case 5d: --all removes a TRACKED name the ref never had. Tracked and absent
# from the ref is git's own evidence the experiment added it, so removing it is
# provably a return to the pre-strip state.
mkdir -p "$repo/.claude"
printf 'committed during the experiment\n' >"$repo/.claude/CLAUDE.md"
git -C "$repo" add .claude/CLAUDE.md
git -C "$repo" commit --quiet -m "experiment added an instruction file"
out="$("$SCRIPT" restore "$repo" "$base" --all)"
case "$out" in
*"removed .claude/CLAUDE.md"*) pass "abandon: a tracked addition is removed" ;;
*) fail "abandon: a tracked addition is removed" "got [$out]" ;;
esac
assert_absent "abandon: the tracked addition is off disk" "$repo/.claude/CLAUDE.md"
assert_equals "abandon: and out of the index" \
  "$(git -C "$repo" ls-files .claude/CLAUDE.md)" ""

# An UNTRACKED name the ref never had is the case git cannot decide: a file that
# was never tracked is absent from every commit, so one the experiment wrote and
# one that predated it (an intentionally untracked CLAUDE.local.md, or a file the
# plan classified convention and kept) look identical. Deleting it would be
# unrecoverable, so it is named and left.
printf 'predates the experiment, never tracked\n' >"$repo/CLAUDE.local.md"
out="$("$SCRIPT" restore "$repo" "$base" --all 2>&1)"
rc=$?
assert_equals "abandon: an undecidable untracked file does not fail the run" "$rc" "0"
assert_file_is "abandon: a pre-existing untracked file is NOT deleted" \
  "$repo/CLAUDE.local.md" "predates the experiment, never tracked"
case "$out" in
*"left in place, untracked"*CLAUDE.local.md*) pass "abandon: it is named for the operator" ;;
*) fail "abandon: it is named for the operator" "got [$out]" ;;
esac
rm -f "$repo/CLAUDE.local.md"

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

# An approved name that is not on disk is a stale plan, not a no-op. Exit 0 here
# would let the manifest record a bare baseline while the named surface still
# loads from wherever it actually moved to.
out="$("$SCRIPT" strip "$repo" .claude/CLAUDE.md 2>&1)"
rc=$?
assert_equals "stale: an approved name that is absent exits 2" "$rc" "2"
case "$out" in
*".claude/CLAUDE.md"*) pass "stale: the message names the absent file" ;;
*) fail "stale: the message names the absent file" "got [$out]" ;;
esac
assert_file_is "stale: and strips nothing" "$repo/AGENTS.md" "team conventions"

# --all keeps the opposite reading: the set is every name PRESENT, so an absent
# one is simply not in it and is not an error.
out="$("$SCRIPT" strip "$repo" --all)"
assert_equals "selective: --all strips what is there without faulting the rest" \
  "$out" "AGENTS.md"

# --- Case 5f: a repeated name is acted on once. Two `git rm`s on one file means
# the second fails after the first already mutated the tree, which is the
# reports-failure-having-done-half-the-work state refused everywhere else here.
repo="$(make_repo dupe 'CLAUDE.md=behavioral lines' 'AGENTS.md=more lines')"
out="$("$SCRIPT" strip "$repo" CLAUDE.md CLAUDE.md 2>&1)"
rc=$?
assert_equals "dupe: a repeated name exits 0" "$rc" "0"
assert_equals "dupe: and is reported once" "$out" "CLAUDE.md"
assert_absent "dupe: the file is stripped" "$repo/CLAUDE.md"
assert_file_is "dupe: the other file is untouched" "$repo/AGENTS.md" "more lines"

# --- Case 5g: an addition that exists only in the INDEX. The worktree test alone
# misses it, and the next commit would carry the experiment's own instruction
# file into the state the abandon was supposed to restore.
repo="$(make_repo indexonly 'CLAUDE.md=original')"
base="$(git -C "$repo" rev-parse HEAD)"
"$SCRIPT" strip "$repo" --all >/dev/null
git -C "$repo" commit --quiet -m "strip"
printf 'staged during the experiment\n' >"$repo/AGENTS.md"
git -C "$repo" add AGENTS.md
rm -f "$repo/AGENTS.md"
out="$("$SCRIPT" restore "$repo" "$base" --all)"
case "$out" in
*"removed AGENTS.md"*) pass "index-only: --all reports removing the staged addition" ;;
*) fail "index-only: --all reports removing the staged addition" "got [$out]" ;;
esac
assert_equals "index-only: the staged addition leaves the index" \
  "$(git -C "$repo" ls-files AGENTS.md)" ""
assert_file_is "index-only: and the pre-strip file is back" "$repo/CLAUDE.md" "original"

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
# The refusal routes rather than dead-ends: an untracked file the plan classified
# behavioral is stripped through the manifest's backup path, not by this helper,
# so the message has to say where it goes.
case "$out" in
*manifest*) pass "untracked: the message routes it to the manifest path" ;;
*) fail "untracked: the message routes it to the manifest path" "got [$out]" ;;
esac
# The tracked files beside it are strippable once it is out of the named set,
# so the refusal does not block the rest of the plan.
out="$("$SCRIPT" strip "$repo" CLAUDE.md AGENTS.md)"
assert_equals "untracked: the tracked files still strip when not named with it" \
  "$out" "CLAUDE.md
AGENTS.md"
assert_file_is "untracked: and the untracked one is left for the manifest path" \
  "$repo/CLAUDE.local.md" "local only"

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
