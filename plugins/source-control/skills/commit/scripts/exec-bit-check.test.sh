#!/usr/bin/env bash
# Regression tests for exec-bit-check.sh.
#
# Black-box: build throwaway git fixtures under a mktemp dir and exercise the
# detection scope (newly-added only, shebang only, 100644 only, symlinks and
# deletions skipped), the three output modes, the worktree-then-index fix
# ordering, pathspec limiting, and the error exits. No network, no writes
# outside the temp dir.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/exec-bit-check.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=../../../scripts/test-helpers.sh
source "$SCRIPT_DIR/../../../scripts/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"
[[ -f "$HELPER" ]] || skip_suite "exec-bit-check.sh not found at $HELPER"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

REPO_SEQ=0

# mkrepo — create a fresh git repo fixture with one commit. Echoes its path as
# the sole stdout line (git noise discarded so command substitution is clean).
mkrepo() {
  REPO_SEQ=$((REPO_SEQ + 1))
  local repo="$TEST_TMPDIR/repo$REPO_SEQ"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q .
    git config user.email test@example.com
    git config user.name "Test User"
    git config commit.gpgsign false
    printf 'seed\n' >seed.txt
    git add seed.txt
    git commit -qm "seed"
  ) >/dev/null 2>&1
  printf '%s\n' "$repo"
}

# staged_mode <repo> <path> — the mode git recorded in the index for <path>.
staged_mode() {
  (cd "$1" && git ls-files --stage -- "$2" 2>/dev/null | head -n 1 | cut -d' ' -f1)
}

# --- Case group 1: detection scope -------------------------------------------

repo="$(mkrepo)"
(
  cd "$repo" || exit 1
  printf '#!/usr/bin/env bash\necho hi\n' >new-script.sh
  printf 'plain text, no shebang\n' >notes.txt
  printf '#!/usr/bin/env bash\necho ok\n' >already-exec.sh
  git add new-script.sh notes.txt already-exec.sh
  # The already-executable fixture is staged 100755 via update-index, NOT via
  # `chmod +x` before `git add`. Under core.filemode=false — the default on
  # Windows/NTFS, verified in this repo — git ignores the worktree permission
  # bits entirely and stages everything 100644, so a chmod-built fixture is
  # 100755 on Linux and 100644 on Windows and the case tests different things
  # per platform. update-index writes the index entry directly and is exact
  # everywhere.
  git update-index --chmod=+x -- already-exec.sh
) >/dev/null 2>&1

out="$(bash "$HELPER" --repo-dir "$repo" --list 2>/dev/null)"
assert_contains "reports a newly-added shebang file staged 100644" "$out" "new-script.sh"
assert_not_contains "ignores a newly-added file with no shebang" "$out" "notes.txt"
assert_not_contains "ignores a newly-added shebang file already staged 100755" "$out" "already-exec.sh"

probe="$(bash "$HELPER" --repo-dir "$repo" --probe 2>/dev/null)"
assert_contains "probe names the offending path" "$probe" "new-script.sh"
assert_contains "probe reports the count" "$probe" "1 staged shebang file(s)"

# --list must stay report-only: a finding is not an error exit, so a
# pre-computed context probe can never fail a skill invocation.
bash "$HELPER" --repo-dir "$repo" --list >/dev/null 2>&1
assert_exit "--list exits 0 even with findings" 0 "$?"

# --- Case group 2: already-tracked files are out of scope ---------------------

repo2="$(mkrepo)"
(
  cd "$repo2" || exit 1
  printf '#!/usr/bin/env bash\necho v1\n' >tracked.sh
  git add tracked.sh
  git commit -qm "add tracked.sh"
  printf '#!/usr/bin/env bash\necho v2\n' >tracked.sh
  git add tracked.sh
) >/dev/null 2>&1

out2="$(bash "$HELPER" --repo-dir "$repo2" --list 2>/dev/null)"
assert_silent "an already-tracked (M) shebang file is not reported" "$out2"

# --- Case group 3: staged deletion is not an add ------------------------------

repo3="$(mkrepo)"
(
  cd "$repo3" || exit 1
  printf '#!/usr/bin/env bash\necho gone\n' >doomed.sh
  git add doomed.sh
  git commit -qm "add doomed.sh"
  git rm -q --cached doomed.sh
) >/dev/null 2>&1

out3="$(bash "$HELPER" --repo-dir "$repo3" --list 2>/dev/null)"
assert_silent "a staged deletion (D) is not reported as an add" "$out3"

# --- Case group 4: symlinks are skipped before the shebang probe --------------

repo4="$(mkrepo)"
symlink_ok=1
(
  cd "$repo4" || exit 1
  printf '#!/usr/bin/env bash\necho target\n' >target.sh
  ln -s target.sh link.sh
) >/dev/null 2>&1 || symlink_ok=0

if [[ "$symlink_ok" -eq 1 ]] && [[ -L "$repo4/link.sh" ]]; then
  (cd "$repo4" && git add target.sh link.sh) >/dev/null 2>&1
  link_mode="$(staged_mode "$repo4" "link.sh")"
  if [[ "$link_mode" == "120000" ]]; then
    out4="$(bash "$HELPER" --repo-dir "$repo4" --list 2>/dev/null)"
    assert_not_contains "a symlink (mode 120000) is never reported" "$out4" "link.sh"
  else
    skip_case "symlink staged as $link_mode, not 120000 (core.symlinks off)"
  fi
else
  skip_case "symlinks unsupported on this platform"
fi

# --- Case group 5: --fix sets BOTH the worktree bit and the index -------------

repo5="$(mkrepo)"
(
  cd "$repo5" || exit 1
  printf '#!/usr/bin/env bash\necho fixme\n' >fixme.sh
  git add fixme.sh
) >/dev/null 2>&1

assert_eq "before --fix the index records 100644" "100644" "$(staged_mode "$repo5" fixme.sh)"

fix_out="$(bash "$HELPER" --repo-dir "$repo5" --fix -- fixme.sh 2>&1)"
fix_rc=$?
assert_exit "--fix exits 0 on success" 0 "$fix_rc"
assert_contains "--fix names the path it fixed" "$fix_out" "fixme.sh"
assert_eq "after --fix the index records 100755" "100755" "$(staged_mode "$repo5" fixme.sh)"

# The index alone is not enough: a later `git add` re-reads the worktree mode
# and would revert the entry to 100644 if only the index had been touched.
if [[ -x "$repo5/fixme.sh" ]]; then
  pass "after --fix the worktree file is executable"
else
  skip_case "worktree exec bit not observable on this filesystem"
fi

(cd "$repo5" && git add fixme.sh) >/dev/null 2>&1
assert_eq "the fix survives a subsequent git add" "100755" "$(staged_mode "$repo5" fixme.sh)"

after="$(bash "$HELPER" --repo-dir "$repo5" --list 2>/dev/null)"
assert_silent "nothing remains to report after --fix" "$after"

nothing="$(bash "$HELPER" --repo-dir "$repo5" --fix -- fixme.sh 2>&1)"
assert_contains "--fix on a clean tree says so" "$nothing" "nothing to fix"

clean_probe="$(bash "$HELPER" --repo-dir "$repo5" --probe 2>/dev/null)"
assert_eq "probe prints 'none' when clean" "none" "$clean_probe"

# --- Case group 5b: --fix works under core.filemode=false ---------------------
#
# The regression this guards: under core.filemode=false, `chmod +x` is invisible
# to git, so a fix that stopped at the worktree bit would leave the index at
# 100644 forever and ship a non-executable blob. Pinned explicitly rather than
# inherited from the host platform so the case tests the same thing everywhere.

repo5b="$(mkrepo)"
(
  cd "$repo5b" || exit 1
  git config core.filemode false
  printf '#!/usr/bin/env bash\necho nofilemode\n' >nofilemode.sh
  git add nofilemode.sh
) >/dev/null 2>&1

out5b="$(bash "$HELPER" --repo-dir "$repo5b" --list 2>/dev/null)"
assert_contains "detects the offender under core.filemode=false" "$out5b" "nofilemode.sh"

bash "$HELPER" --repo-dir "$repo5b" --fix -- nofilemode.sh >/dev/null 2>&1
assert_eq "--fix reaches the index under core.filemode=false" \
  "100755" "$(staged_mode "$repo5b" nofilemode.sh)"

# --- Case group 6: pathspec limiting -----------------------------------------

repo6="$(mkrepo)"
(
  cd "$repo6" || exit 1
  mkdir -p tools other
  printf '#!/usr/bin/env bash\necho a\n' >tools/a.sh
  printf '#!/usr/bin/env bash\necho b\n' >other/b.sh
  git add tools/a.sh other/b.sh
) >/dev/null 2>&1

scoped="$(bash "$HELPER" --repo-dir "$repo6" --list -- tools 2>/dev/null)"
assert_contains "pathspec keeps the in-scope path" "$scoped" "tools/a.sh"
assert_not_contains "pathspec excludes the out-of-scope path" "$scoped" "other/b.sh"

# --- Case group 7: paths containing a space ----------------------------------

repo7="$(mkrepo)"
(
  cd "$repo7" || exit 1
  printf '#!/usr/bin/env bash\necho spaced\n' >"my script.sh"
  git add "my script.sh"
) >/dev/null 2>&1

out7="$(bash "$HELPER" --repo-dir "$repo7" --list 2>/dev/null)"
assert_contains "a path containing a space is reported intact" "$out7" "my script.sh"

bash "$HELPER" --repo-dir "$repo7" --fix -- "my script.sh" >/dev/null 2>&1
assert_eq "a path containing a space is fixed" "100755" "$(staged_mode "$repo7" "my script.sh")"

# --- Case group 8: error exits ------------------------------------------------

bash "$HELPER" --repo-dir "$repo" --bogus-flag >/dev/null 2>&1
assert_exit "unknown argument exits 2" 2 "$?"

bash "$HELPER" --repo-dir >/dev/null 2>&1
assert_exit "--repo-dir with no value exits 2" 2 "$?"

nonrepo="$TEST_TMPDIR/not-a-repo"
mkdir -p "$nonrepo"
bash "$HELPER" --repo-dir "$nonrepo" --list >/dev/null 2>&1
assert_exit "a non-repository exits 3" 3 "$?"

bash "$HELPER" --repo-dir "$TEST_TMPDIR/does-not-exist" --list >/dev/null 2>&1
assert_exit "an unreachable --repo-dir exits 3" 3 "$?"

bash "$HELPER" --help >/dev/null 2>&1
assert_exit "--help exits 0" 0 "$?"

# --- Case group 8b: --fix refuses an unscoped run -----------------------------
#
# --fix mutates index entries, so an unscoped run could silently rewrite a
# concurrent session's staged modes — the blanket mutation this skill's
# surgical-staging discipline exists to prevent. Read-only modes stay unscoped.

repo8b="$(mkrepo)"
(
  cd "$repo8b" || exit 1
  printf '#!/usr/bin/env bash\necho scoped\n' >scoped.sh
  git add scoped.sh
) >/dev/null 2>&1

refusal="$(bash "$HELPER" --repo-dir "$repo8b" --fix 2>&1)"
refuse_rc=$?
assert_exit "bare --fix refuses with exit 2" 2 "$refuse_rc"
assert_contains "the refusal explains the required scope" "$refusal" "needs an explicit scope"
assert_eq "a refused --fix mutates nothing" "100644" "$(staged_mode "$repo8b" scoped.sh)"

bash "$HELPER" --repo-dir "$repo8b" --list >/dev/null 2>&1
assert_exit "--list stays unscoped and exits 0" 0 "$?"

bash "$HELPER" --repo-dir "$repo8b" --probe >/dev/null 2>&1
assert_exit "--probe stays unscoped and exits 0" 0 "$?"

bash "$HELPER" --repo-dir "$repo8b" --fix -- scoped.sh >/dev/null 2>&1
assert_eq "--fix with an explicit pathspec is allowed" "100755" "$(staged_mode "$repo8b" scoped.sh)"

repo8c="$(mkrepo)"
(
  cd "$repo8c" || exit 1
  printf '#!/usr/bin/env bash\necho swept\n' >swept.sh
  git add swept.sh
) >/dev/null 2>&1

bash "$HELPER" --repo-dir "$repo8c" --fix --all >/dev/null 2>&1
assert_eq "--fix --all is the explicit whole-index opt-in" "100755" "$(staged_mode "$repo8c" swept.sh)"

# --- Case group 9: empty index is a clean no-op -------------------------------

repo9="$(mkrepo)"
empty="$(bash "$HELPER" --repo-dir "$repo9" --list 2>/dev/null)"
assert_silent "an empty staged set reports nothing" "$empty"
bash "$HELPER" --repo-dir "$repo9" --list >/dev/null 2>&1
assert_exit "an empty staged set exits 0" 0 "$?"

# --- Case group 10: runs from a subdirectory ----------------------------------
#
# The regression this guards: `git diff --cached --name-status` emits
# repo-root-relative paths while a `git ls-files` pathspec resolves against the
# cwd. Run from a subdirectory those disagree, every lookup misses, and the
# check silently reports NO offenders — a fail-open backstop.

repo10="$(mkrepo)"
(
  cd "$repo10" || exit 1
  mkdir -p sub/nested
  printf '#!/usr/bin/env bash\necho deep\n' >sub/nested/deep.sh
  printf '#!/usr/bin/env bash\necho top\n' >toplevel.sh
  git add sub/nested/deep.sh toplevel.sh
) >/dev/null 2>&1

from_sub="$(cd "$repo10/sub" && bash "$HELPER" --list 2>/dev/null)"
assert_contains "run from a subdirectory still sees the root-level offender" "$from_sub" "toplevel.sh"
assert_contains "run from a subdirectory still sees the nested offender" "$from_sub" "sub/nested/deep.sh"

sub_probe="$(cd "$repo10/sub" && bash "$HELPER" --probe 2>/dev/null)"
assert_contains "probe from a subdirectory reports both offenders" "$sub_probe" "2 staged shebang file(s)"

# A caller's pathspec is relative to the CALLER's cwd, so it must be re-anchored
# before the directory change or a scoped --fix silently matches nothing.
(cd "$repo10/sub" && bash "$HELPER" --fix -- nested/deep.sh) >/dev/null 2>&1
assert_eq "a cwd-relative pathspec from a subdirectory is re-anchored and fixed" \
  "100755" "$(staged_mode "$repo10" sub/nested/deep.sh)"
assert_eq "the re-anchored --fix did not touch the out-of-scope path" \
  "100644" "$(staged_mode "$repo10" toplevel.sh)"

# --- Case group 11: a worktree symlink is refused, never chmod-ed -------------
#
# A path staged as a regular 100644 blob but replaced in the worktree by a
# symlink: `-e` follows the link, so an unguarded chmod would make the link's
# TARGET executable — a file that can sit entirely outside the repository.

repo11="$(mkrepo)"
sym_ok=1
(
  cd "$repo11" || exit 1
  printf '#!/usr/bin/env bash\necho real\n' >swapped.sh
  git add swapped.sh
  mkdir -p outside
  printf 'not a script\n' >outside/victim.txt
  rm -f swapped.sh
  ln -s outside/victim.txt swapped.sh
) >/dev/null 2>&1 || sym_ok=0

if [[ "$sym_ok" -eq 1 ]] && [[ -L "$repo11/swapped.sh" ]]; then
  sym_out="$(bash "$HELPER" --repo-dir "$repo11" --fix -- swapped.sh 2>&1)"
  sym_rc=$?
  assert_exit "a worktree symlink over a staged regular file fails --fix" 4 "$sym_rc"
  assert_contains "the refusal names the symlink mismatch" "$sym_out" "worktree entry is a symlink"
  if [[ -x "$repo11/outside/victim.txt" ]]; then
    fail "the symlink target must not become executable" "not executable" "executable"
  else
    pass "the symlink target was not made executable"
  fi
else
  skip_case "symlinks unsupported on this platform"
fi

# --- Case group 12: NUL-delimited list mode -----------------------------------

repo12="$(mkrepo)"
(
  cd "$repo12" || exit 1
  printf '#!/usr/bin/env bash\necho one\n' >one.sh
  printf '#!/usr/bin/env bash\necho two\n' >two.sh
  git add one.sh two.sh
) >/dev/null 2>&1

nul_count="$(bash "$HELPER" --repo-dir "$repo12" --list0 2>/dev/null | tr -dc '\0' | wc -c | tr -d ' \r')"
assert_eq "--list0 emits one NUL terminator per offender" "2" "$nul_count"

bash "$HELPER" --repo-dir "$repo12" --list0 >/dev/null 2>&1
assert_exit "--list0 exits 0" 0 "$?"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
