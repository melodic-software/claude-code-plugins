#!/usr/bin/env bash
set -uo pipefail

# Isolate the fixture repositories from any ambient git environment: `git -C`
# changes directory but does not override discovery, so an exported GIT_DIR
# would land these throwaway identities in the CALLER's .git/config.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/instruction-files.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=../../../lib/test-helpers.sh
source "$SCRIPT_DIR/../../../lib/test-helpers.sh"

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

out="$("$SCRIPT" restore "$repo" "$base" AGENTS.md)"
assert_equals "shim: a named restore reports only the file it was asked for" \
  "$out" "AGENTS.md"
assert_file_is "shim: the named file is restored byte for byte" \
  "$repo/AGENTS.md" "root instructions"
assert_absent "shim: an unnamed file stays stripped" "$repo/.claude/AGENTS.md"
assert_absent "shim: the other unnamed file stays stripped" "$repo/CLAUDE.md"

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

rm -f "$repo/CLAUDE.md"
mkdir -p "$repo/CLAUDE.md"
printf 'keep me\n' >"$repo/CLAUDE.md/inner.txt"
out="$("$SCRIPT" restore "$repo" "$base" CLAUDE.md 2>&1)"
rc=$?
assert_equals "collide: a directory on the target exits 2" "$rc" "2"
assert_file_is "collide: the directory's contents survive" \
  "$repo/CLAUDE.md/inner.txt" "keep me"
case "$out" in
*occupied*) pass "collide: the refusal names the reason it resolved" ;;
*) fail "collide: the refusal names the reason it resolved" "got [$out]" ;;
esac
rm -rf "$repo/CLAUDE.md"

rm -rf "$repo/.claude"
printf 'a file where the directory goes\n' >"$repo/.claude"
out="$("$SCRIPT" restore "$repo" "$base" .claude/AGENTS.md 2>&1)"
rc=$?
assert_equals "collide: a non-directory ancestor exits 2" "$rc" "2"
assert_file_is "collide: the blocking ancestor survives" \
  "$repo/.claude" "a file where the directory goes"
case "$out" in
*blocked-ancestor*) pass "collide: an ancestor block is named as such, not as 'present'" ;;
*) fail "collide: an ancestor block is named as such, not as 'present'" "got [$out]" ;;
esac

out="$("$SCRIPT" restore "$repo" "$base" --all 2>&1)"
assert_file_is "collide: --all leaves the blocking ancestor alone" \
  "$repo/.claude" "a file where the directory goes"
case "$out" in
*"blocked by another object"*) pass "collide: --all reports what it stepped over" ;;
*) fail "collide: --all reports what it stepped over" "got [$out]" ;;
esac
rm -f "$repo/.claude"

repo="$(make_repo abort 'CLAUDE.md=original')"
base="$(git -C "$repo" rev-parse HEAD)"
"$SCRIPT" strip "$repo" --all >/dev/null
git -C "$repo" commit --quiet -m "strip"
printf 'added by the experiment\n' >"$repo/AGENTS.md"
git -C "$repo" add AGENTS.md
git -C "$repo" commit --quiet -m "experiment added an instruction file"
rm -f "$repo/AGENTS.md"
mkdir -p "$repo/AGENTS.md"
printf 'not an instruction file\n' >"$repo/AGENTS.md/inner.txt"
out="$("$SCRIPT" restore "$repo" "$base" --all 2>&1)"
rc=$?
assert_equals "abort: --all completes rather than dying on the obstruction" "$rc" "0"
assert_file_is "abort: the earlier name is still restored" "$repo/CLAUDE.md" "original"
assert_file_is "abort: the obstructing directory survives" \
  "$repo/AGENTS.md/inner.txt" "not an instruction file"
case "$out" in
*fatal:*) fail "abort: no raw git fatal reaches the operator" "got [$out]" ;;
*) pass "abort: no raw git fatal reaches the operator" ;;
esac
assert_equals "abort: the index entry is dropped even though the object stays" \
  "$(git -C "$repo" ls-files AGENTS.md)" ""

# Symlinks: `-f` follows them, so a link to a regular file would look like an
# ordinary file and be silently replaced. Real symlinks are unavailable on some
# hosts (Windows without privilege), so this case announces a skip rather than
# passing vacuously; CI's Linux legs do exercise it.
symlink_repo="$(make_repo symlink 'CLAUDE.md=original' 'target.md=link target')"
if ln -s target.md "$symlink_repo/AGENTS.md" 2>/dev/null && [[ -L "$symlink_repo/AGENTS.md" ]]; then
  sbase="$(git -C "$symlink_repo" rev-parse HEAD)"
  out="$("$SCRIPT" restore "$symlink_repo" "$sbase" --all 2>&1)"
  assert_equals "symlink: --all leaves a symlink at a name alone" \
    "$(readlink "$symlink_repo/AGENTS.md")" "target.md"
  case "$out" in
  *"blocked by another object"*) pass "symlink: --all reports the link it stepped over" ;;
  *) fail "symlink: --all reports the link it stepped over" "got [$out]" ;;
  esac
  assert_file_is "symlink: the link's target is untouched" \
    "$symlink_repo/target.md" "link target"

  # A SYMLINKED ANCESTOR. `-d` follows the link, so a `.claude` pointing at a
  # real directory reads as an ordinary one; writing `.claude/AGENTS.md` through
  # it replaces the link with a real directory and the link is lost.
  ancestor_repo="$(make_repo symlink_ancestor '.claude/AGENTS.md=dot instructions' 'README.md=code')"
  abase="$(git -C "$ancestor_repo" rev-parse HEAD)"
  "$SCRIPT" strip "$ancestor_repo" --all >/dev/null
  git -C "$ancestor_repo" commit --quiet -m "strip"
  rm -rf "$ancestor_repo/.claude"
  mkdir -p "$ancestor_repo/elsewhere"
  ln -s elsewhere "$ancestor_repo/.claude"
  out="$("$SCRIPT" restore "$ancestor_repo" "$abase" .claude/AGENTS.md 2>&1)"
  rc=$?
  assert_equals "symlink-ancestor: a named restore through a linked ancestor exits 2" "$rc" "2"
  assert_equals "symlink-ancestor: the link survives" \
    "$(readlink "$ancestor_repo/.claude")" "elsewhere"

  # And a DANGLING ancestor link, which fails -e and would pass a test that only
  # asked whether the path is a non-directory.
  rm -f "$ancestor_repo/.claude"
  ln -s nowhere-at-all "$ancestor_repo/.claude"
  out="$("$SCRIPT" restore "$ancestor_repo" "$abase" .claude/AGENTS.md 2>&1)"
  rc=$?
  assert_equals "symlink-ancestor: a dangling linked ancestor also exits 2" "$rc" "2"
  assert_equals "symlink-ancestor: the dangling link survives" \
    "$(readlink "$ancestor_repo/.claude")" "nowhere-at-all"
else
  echo "SKIP: symlinks unavailable on this host; the symlink obstruction cases did not run" >&2
fi

# --- Case 5a4: content that exists ONLY in the index. The name is recreated,
# staged, then deleted from the worktree, so every filesystem test reports the
# path free while the staged blob is real content. `git checkout <ref> -- <path>`
# writes the index as well as the worktree, so it would discard that blob.
repo="$(make_repo staged 'CLAUDE.md=committed')"
base="$(git -C "$repo" rev-parse HEAD)"
"$SCRIPT" strip "$repo" --all >/dev/null
git -C "$repo" commit --quiet -m "strip"
printf 'staged work nobody committed\n' >"$repo/CLAUDE.md"
git -C "$repo" add CLAUDE.md
rm -f "$repo/CLAUDE.md"
out="$("$SCRIPT" restore "$repo" "$base" CLAUDE.md 2>&1)"
rc=$?
assert_equals "staged-only: a named restore over staged-only content exits 2" "$rc" "2"
case "$out" in
*staged-in-index*) pass "staged-only: the refusal names the index as the occupant" ;;
*) fail "staged-only: the refusal names the index as the occupant" "got [$out]" ;;
esac
assert_equals "staged-only: the staged blob is still the one in the index" \
  "$(git -C "$repo" show :CLAUDE.md)" "staged work nobody committed"
case "$out" in
*"git rm --cached"*) pass "staged-only: the refusal names a command, not just a state" ;;
*) fail "staged-only: the refusal names a command, not just a state" "got [$out]" ;;
esac

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

printf 'rewritten during the experiment\n' >"$repo/AGENTS.md"
out="$("$SCRIPT" restore "$repo" "$base" --all)"
assert_equals "overwrite: --all reports the file it took back" "$out" "CLAUDE.md
AGENTS.md"
assert_file_is "overwrite: the rewritten file is returned to its pre-strip content" \
  "$repo/AGENTS.md" "root instructions"

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

out="$("$SCRIPT" strip "$repo" .claude/CLAUDE.md 2>&1)"
rc=$?
assert_equals "stale: an approved name that is absent exits 2" "$rc" "2"
case "$out" in
*".claude/CLAUDE.md"*) pass "stale: the message names the absent file" ;;
*) fail "stale: the message names the absent file" "got [$out]" ;;
esac
assert_file_is "stale: and strips nothing" "$repo/AGENTS.md" "team conventions"

out="$("$SCRIPT" strip "$repo" --all)"
assert_equals "selective: --all strips what is there without faulting the rest" \
  "$out" "AGENTS.md"

repo="$(make_repo dupe 'CLAUDE.md=behavioral lines' 'AGENTS.md=more lines')"
out="$("$SCRIPT" strip "$repo" CLAUDE.md CLAUDE.md 2>&1)"
rc=$?
assert_equals "dupe: a repeated name exits 0" "$rc" "0"
assert_equals "dupe: and is reported once" "$out" "CLAUDE.md"
assert_absent "dupe: the file is stripped" "$repo/CLAUDE.md"
assert_file_is "dupe: the other file is untouched" "$repo/AGENTS.md" "more lines"

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

repo="$(make_repo lone 'AGENTS.md=lone instructions' 'README.md=code')"
base="$(git -C "$repo" rev-parse HEAD)"
assert_equals "lone: list finds the AGENTS.md and nothing else" \
  "$("$SCRIPT" list "$repo")" "AGENTS.md"
"$SCRIPT" strip "$repo" --all >/dev/null
assert_absent "lone: AGENTS.md is stripped" "$repo/AGENTS.md"
git -C "$repo" commit --quiet -m "strip"
"$SCRIPT" restore "$repo" "$base" AGENTS.md >/dev/null
assert_file_is "lone: AGENTS.md comes back" "$repo/AGENTS.md" "lone instructions"

repo="$(make_repo dotclaude '.claude/AGENTS.md=dot-claude only')"
base="$(git -C "$repo" rev-parse HEAD)"
"$SCRIPT" strip "$repo" --all >/dev/null
assert_absent "dot-claude: the file is stripped" "$repo/.claude/AGENTS.md"
git -C "$repo" commit --quiet -m "strip"
"$SCRIPT" restore "$repo" "$base" .claude/AGENTS.md >/dev/null
assert_file_is "dot-claude: the file comes back with its directory" \
  "$repo/.claude/AGENTS.md" "dot-claude only"

repo="$(make_repo bare 'README.md=code')"
out="$("$SCRIPT" list "$repo")"
rc=$?
assert_equals "bare: list prints nothing" "$out" ""
assert_equals "bare: list exits 0" "$rc" "0"
"$SCRIPT" strip "$repo" --all >/dev/null
assert_equals "bare: strip leaves the tree clean" "$(git -C "$repo" status --porcelain)" ""

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
case "$out" in
*manifest*) pass "untracked: the message routes it to the manifest path" ;;
*) fail "untracked: the message routes it to the manifest path" "got [$out]" ;;
esac
out="$("$SCRIPT" strip "$repo" CLAUDE.md AGENTS.md)"
assert_equals "untracked: the tracked files still strip when not named with it" \
  "$out" "CLAUDE.md
AGENTS.md"
assert_file_is "untracked: and the untracked one is left for the manifest path" \
  "$repo/CLAUDE.local.md" "local only"

# --- Case 6b: assume-unchanged hides the edit from both diff checks. Measured:
# `ls-files -v` prints `h`, both `git diff --quiet` calls exit 0, and `git rm`
# then deletes the uncommitted contents with nothing in the ref to recover. The
# index bit is the only signal the clean answer is not trustworthy.
repo="$(make_repo assume 'CLAUDE.md=committed content' 'AGENTS.md=other')"
git -C "$repo" update-index --assume-unchanged CLAUDE.md
printf 'edited after the bit was set\n' >"$repo/CLAUDE.md"
out="$("$SCRIPT" strip "$repo" --all 2>&1)"
rc=$?
assert_equals "assume-unchanged: strip exits 2 rather than destroying the edit" "$rc" "2"
assert_file_is "assume-unchanged: the local edit survives" \
  "$repo/CLAUDE.md" "edited after the bit was set"
case "$out" in
*assume-unchanged*) pass "assume-unchanged: the message names the bit and how to clear it" ;;
*) fail "assume-unchanged: the message names the bit and how to clear it" "got [$out]" ;;
esac
assert_file_is "assume-unchanged: the file beside it is untouched too" \
  "$repo/AGENTS.md" "other"
git -C "$repo" update-index --no-assume-unchanged CLAUDE.md
out="$("$SCRIPT" strip "$repo" --all 2>&1)"
rc=$?
assert_equals "assume-unchanged: with the bit cleared it is a plain modified refusal" "$rc" "2"
case "$out" in
*modified*) pass "assume-unchanged: and the reason changes to modified" ;;
*) fail "assume-unchanged: and the reason changes to modified" "got [$out]" ;;
esac

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

git -C "$repo" add AGENTS.md
out="$("$SCRIPT" strip "$repo" --all 2>&1)"
rc=$?
assert_equals "staged: strip exits 2" "$rc" "2"
assert_file_is "staged: the earlier CLAUDE.md is NOT removed" "$repo/CLAUDE.md" "@AGENTS.md"

git -C "$repo" commit --quiet -m "edit"
out="$("$SCRIPT" strip "$repo" --all)"
assert_equals "committed: the strip now covers both files" \
  "$out" "CLAUDE.md
AGENTS.md"

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
