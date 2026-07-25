#!/usr/bin/env bash
# Regression tests for worktree-create.sh (Phase A).
# Black-box: build throwaway git fixtures under a mktemp dir, exercise path
# computation, the refuse-when-unconfigured contract, slug sanitization,
# base-ref resolution, and the .worktreeinclude copy intersection. No network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/worktree-create.sh"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v git >/dev/null 2>&1 || skip_suite "git not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# mkrepo [--origin <url>] [--no-head] — create a fresh git repo fixture with one
# commit; unless --no-head, origin/HEAD is pointed at the default branch. Echoes
# the repo path (the sole stdout line; all git noise is discarded so command
# substitution captures only the path). Each call gets a unique dir — the
# function body runs in a command-substitution subshell, so a mutating counter
# would not persist.
mkrepo() {
  local origin_url="" seed_head=1
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --origin) origin_url="$2"; shift 2 ;;
      --no-head) seed_head=0; shift ;;
      *) shift ;;
    esac
  done
  local repo
  repo="$(mktemp -d "$TEST_TMPDIR/repoXXXXXX")"
  {
    git -C "$repo" init -q -b main
    git -C "$repo" config user.email t@t.t
    git -C "$repo" config user.name t
    printf 'seed\n' > "$repo/README.md"
    git -C "$repo" add README.md
    git -C "$repo" commit -qm init
    if [[ -n "$origin_url" ]]; then
      git -C "$repo" remote add origin "$origin_url"
      if [[ "$seed_head" == 1 ]]; then
        # Point origin/HEAD at main without a network fetch so `fresh` resolves.
        git -C "$repo" update-ref refs/remotes/origin/main "$(git -C "$repo" rev-parse HEAD)"
        git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
      fi
    fi
  } >/dev/null 2>&1
  printf '%s' "$repo"
}

# --- Case: --help exits 0 and documents the refuse contract ---
help_out=$(bash "$HELPER" --help 2>&1)
assert_exit "--help exit 0" 0 "$?"
assert_contains "--help documents refuse (exit 3)" "$help_out" "refuse"

# --- Case: missing --name -> usage error (exit 2) ---
bash "$HELPER" --root "$TEST_TMPDIR/wt" >/dev/null 2>&1
assert_exit "missing --name exit 2" 2 "$?"

# --- Case: refuse when root empty (exit 3), nothing created ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
err=$(bash "$HELPER" --name feat/x --root "" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "empty root refuses exit 3" 3 "$?"
assert_contains "refuse message names worktree_root key" "$err" "worktree_root"
assert_contains "refuse message rejects in-repo fallback" "$err" ".claude/worktrees/"

# --- Case: refuse when root is an unexpanded userConfig token (exit 3) ---
bash "$HELPER" --name feat/x --root '${user_config.worktree_root}' --repo-dir "$repo" >/dev/null 2>&1
assert_exit "unexpanded token refuses exit 3" 3 "$?"

# --- Case: refuse when the configured root is inside the repo (exit 3) ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
err=$(bash "$HELPER" --name feat/x --root "$repo/.claude/worktrees" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "in-repo root refuses exit 3" 3 "$?"
assert_contains "in-repo refuse names the repository" "$err" "inside the repository"

# --- Case: refuse a relative root that resolves inside the repo (exit 3) ---
# git -C "$toplevel" worktree add anchors a relative target at the repo top level.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
bash "$HELPER" --name feat/x --root "worktrees" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "relative in-repo root refuses exit 3" 3 "$?"

# --- Case: refuse a root nested inside a DIFFERENT checkout (exit 3) ---
# The guard rejects placement inside ANY working tree, not only the source repo:
# a root under an unrelated clone still triggers the nested-checkout double-load bug.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
other=$(mkrepo --origin "git@github.com:acme/other.git")
err=$(bash "$HELPER" --name feat/x --root "$other/nested" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "root inside another checkout refuses exit 3" 3 "$?"
assert_contains "foreign-checkout refuse names another working tree" "$err" "another git working tree"

# --- Case: refuse a root beneath a normal repo's .git directory (exit 3) ---
# `git rev-parse --show-toplevel` fails inside a .git dir, so the work-tree probe
# alone misses it; --is-inside-git-dir catches the git-administrative ancestor
# and stops a linked checkout from landing inside git metadata.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
err=$(bash "$HELPER" --name feat/x --root "$repo/.git/external" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "root under .git refuses exit 3" 3 "$?"
assert_contains "git-dir refuse names a git directory" "$err" "inside a git directory"
assert_file_absent "no worktree created inside .git" "$repo/.git/external/acme-widget-feat-x/README.md"

# --- Case: refuse a root inside a bare clone (exit 3) ---
# A bare repo has no work tree either, so --show-toplevel reports nothing; the
# same --is-inside-git-dir guard rejects the bare-repo ancestor.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
bare="$(mktemp -d "$TEST_TMPDIR/bareXXXXXX")/other.git"
git init -q --bare "$bare" >/dev/null 2>&1
err=$(bash "$HELPER" --name feat/x --root "$bare/worktrees" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "root inside a bare clone refuses exit 3" 3 "$?"
assert_contains "bare-clone refuse names a git directory" "$err" "inside a git directory"

# --- Case: refuse a root with `..` after a NONEXISTENT component (exit 3) ---
# `<tmp>/nonexistent/../<repo>/.claude/worktrees` lexically resolves inside the
# repo, but the raw-string ancestor walk stopped at the nonexistent `nonexistent`
# component and never probed the real repo; `git worktree add` would then create
# the missing dir, resolve `..`, and land the checkout in `.claude/worktrees`.
# Normalizing the target before the walk closes this.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/nonexistent-leading/../${repo##*/}/.claude/worktrees"
err=$(bash "$HELPER" --name feat/x --root "$root" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "'..'-after-nonexistent in-repo root refuses exit 3" 3 "$?"
assert_contains "normalized in-repo refuse names the repository" "$err" "inside the repository"
assert_file_absent "no worktree materialized inside repo via '..' bypass" \
  "$repo/.claude/worktrees/acme-widget-feat-x/README.md"

# --- Case: Windows backslash roots are canonicalized before the guard ---
# On a Windows shell `\` is a separator git resolves but the ancestor walk (which
# splits on `/`) cannot climb, so an un-canonicalized backslash root would skip
# the containment guard entirely. Windows-only: `\` is a legal filename byte
# elsewhere. cygpath -w builds the native backslash form.
if [[ "$OSTYPE" == msys || "$OSTYPE" == cygwin ]] && command -v cygpath >/dev/null 2>&1; then
  # backslash root pointing directly into the repo working tree
  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  err=$(bash "$HELPER" --name feat/bs --root "$(cygpath -w "$repo")\\.claude\\worktrees" --repo-dir "$repo" 2>&1 >/dev/null)
  assert_exit "backslash root inside repo refuses exit 3" 3 "$?"
  assert_contains "backslash in-repo refuse names the repository" "$err" "inside the repository"
  assert_file_absent "no worktree via backslash-into-repo" "$repo/.claude/worktrees/acme-widget-feat-bs/README.md"

  # backslash root pointing into the .git directory
  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  err=$(bash "$HELPER" --name feat/bg --root "$(cygpath -w "$repo")\\.git\\ext" --repo-dir "$repo" 2>&1 >/dev/null)
  assert_exit "backslash root inside .git refuses exit 3" 3 "$?"
  assert_contains "backslash-into-.git names a git directory" "$err" "inside a git directory"

  # backslash root with `..` after a nonexistent component resolving into the repo
  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  bs_dd="$(cygpath -w "$repo")\\..\\missing\\..\\${repo##*/}\\.claude\\worktrees"
  bash "$HELPER" --name feat/bd --root "$bs_dd" --repo-dir "$repo" >/dev/null 2>&1
  assert_exit "backslash + '..' resolving inside repo refuses exit 3" 3 "$?"

  # a genuine EXTERNAL backslash root still creates (exit 0) — no over-reject, and
  # the printed path is the forward-slash form EnterWorktree(path:) expects.
  repo=$(mkrepo --origin "git@github.com:acme/widget.git")
  out=$(bash "$HELPER" --name feat/be --root "$(cygpath -w "$TEST_TMPDIR/ext-backslash")" --repo-dir "$repo" 2>/dev/null)
  assert_exit "external backslash root still creates (exit 0)" 0 "$?"
  assert_file_exists "external backslash worktree materialized" "$out/README.md"
else
  skip_case "backslash-root canonicalization is Windows-only"
fi

# --- Case: an external root adjacent to a .git directory is allowed (exit 0) ---
# Normal-path guard: the containment check must not over-reject a genuinely
# external root just because a sibling path holds a git directory.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/adjacent-external"
out=$(bash "$HELPER" --name feat/adj --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "external root adjacent to a repo still creates (exit 0)" 0 "$?"
assert_file_exists "external adjacent worktree materialized" "$out/README.md"

# --- Case: path computation <root>/<owner>-<repo>-<slug> with slug sanitization ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/wtroot1"
out=$(bash "$HELPER" --name "feat/my-feature" --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "create exit 0" 0 "$?"
assert_eq "computed path is <root>/<owner>-<repo>-<slug>" \
  "$root/acme-widget-feat-my-feature" "$out"
assert_file_exists "worktree checkout materialized" "$out/README.md"
# branch name keeps the slash; only the directory slug is sanitized.
assert_eq "branch keeps original name" "feat/my-feature" \
  "$(git -C "$out" rev-parse --abbrev-ref HEAD)"

# --- Case: https origin URL parses the same owner/repo ---
repo=$(mkrepo --origin "https://github.com/acme/widget.git")
root="$TEST_TMPDIR/wtroot2"
out=$(bash "$HELPER" --name fix/bug --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "https origin -> same owner-repo" "$root/acme-widget-fix-bug" "$out"

# --- Case: no origin remote -> <root>/<repo>-<slug> (owner omitted) ---
repo=$(mkrepo)
root="$TEST_TMPDIR/wtroot3"
out=$(bash "$HELPER" --name chore/tidy --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "no origin -> <repo>-<slug>, owner omitted" \
  "$root/${repo##*/}-chore-tidy" "$out"

# --- Case: target path already exists -> exit 4 ---
bash "$HELPER" --name chore/tidy --root "$root" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "duplicate path exit 4" 4 "$?"

# --- Case: base-ref head branches from local HEAD (carries unpushed commits) ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
printf 'local-only\n' > "$repo/UNPUSHED.md"
git -C "$repo" add UNPUSHED.md
git -C "$repo" commit -qm "unpushed local commit"
root="$TEST_TMPDIR/wtroot4"
out=$(bash "$HELPER" --name feat/head-base --root "$root" --base-ref head --repo-dir "$repo" 2>/dev/null)
assert_file_exists "base-ref head carries the unpushed commit" "$out/UNPUSHED.md"

# --- Case: base-ref fresh branches from origin/HEAD (excludes unpushed) ---
root="$TEST_TMPDIR/wtroot5"
out=$(bash "$HELPER" --name feat/fresh-base --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_file_absent "base-ref fresh excludes the unpushed commit" "$out/UNPUSHED.md"

# --- Case: .worktreeinclude copy is the (matched AND gitignored) intersection ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
printf '.work/\n*.env\n' > "$repo/.gitignore"
printf '.work/keep.md\n.work/*/EXPLORE.md\n*.env\n' > "$repo/.worktreeinclude"
git -C "$repo" add .gitignore .worktreeinclude
git -C "$repo" commit -qm "ignore + include"
mkdir -p "$repo/.work/task1"
printf 'x\n' > "$repo/.work/keep.md"          # matched + gitignored -> copy
printf 'x\n' > "$repo/.work/task1/EXPLORE.md" # matched (nested) + gitignored -> copy
printf 'x\n' > "$repo/.work/task1/OTHER.md"   # gitignored, NOT matched  -> skip
printf 'x\n' > "$repo/secrets.env"            # matched + gitignored -> copy
printf 'x\n' > "$repo/loose.txt"              # neither -> skip
root="$TEST_TMPDIR/wtroot6"
out=$(bash "$HELPER" --name feat/inc --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_file_exists "worktreeinclude: matched+ignored top-level copied" "$out/.work/keep.md"
assert_file_exists "worktreeinclude: matched+ignored nested copied (mkdir -p)" "$out/.work/task1/EXPLORE.md"
assert_file_exists "worktreeinclude: matched+ignored env copied" "$out/secrets.env"
assert_file_absent "worktreeinclude: gitignored-but-unmatched skipped" "$out/.work/task1/OTHER.md"
assert_file_absent "worktreeinclude: unignored file never copied" "$out/loose.txt"

# --- Case: a value-taking flag as the last token errors, does not hang (exit 2) ---
# Regression guard: a failed `shift 2` on a lone positional once spun forever.
for flag in --name --root --base-ref --repo-dir; do
  code=0
  bash "$HELPER" "$flag" >/dev/null 2>&1 || code=$?
  assert_exit "trailing valueless $flag errors (no hang)" 2 "$code"
done

# --- Case: --base-ref fresh with uncached origin/HEAD warns and falls back ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git" --no-head)
root="$TEST_TMPDIR/wtroot7"
err=$(bash "$HELPER" --name feat/nohead --root "$root" --base-ref fresh --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "fresh w/o origin/HEAD still succeeds" 0 "$?"
assert_contains "fresh w/o origin/HEAD warns about fallback" "$err" "could not resolve the remote default branch"
assert_file_exists "fresh fallback still creates the worktree" "$root/acme-widget-feat-nohead/README.md"

# --- Case: 3+-segment URLs — Azure DevOps (_git) and GitLab subgroup ---
repo=$(mkrepo --origin "https://dev.azure.com/myorg/myproject/_git/widget")
root="$TEST_TMPDIR/wtroot8"
out=$(bash "$HELPER" --name feat/az --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "Azure _git URL -> project as owner, repo last" "$root/myproject-widget-feat-az" "$out"

repo=$(mkrepo --origin "https://gitlab.com/group/subgroup/widget.git")
root="$TEST_TMPDIR/wtroot9"
out=$(bash "$HELPER" --name feat/gl --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "GitLab subgroup URL -> subgroup as owner" "$root/subgroup-widget-feat-gl" "$out"

# --- Case: a name with characters git refs reject is refused up front (exit 2) ---
# The branch is used verbatim, so an unsafe name must fail loudly here rather
# than opaquely inside `git worktree add`.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
err=$(bash "$HELPER" --name 'feat/weird @name#v2' --root "$TEST_TMPDIR/wtroot10" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "unsafe-char name refused (exit 2)" 2 "$?"
assert_contains "unsafe-char refusal explains the rule" "$err" "not a valid worktree/branch name"
# An over-long name (>64 chars) is likewise refused.
bash "$HELPER" --name "feat/$(printf 'a%.0s' {1..70})" --root "$TEST_TMPDIR/wtroot10" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "over-64-char name refused (exit 2)" 2 "$?"
# A name whose characters are all in the allowed class but which git rejects as a
# branch is refused here (exit 2) rather than reaching `git worktree add` and
# surfacing as environment exit 4 — the correction flow keys on the usage error.
for badref in 'feat/foo..bar' 'feat/.' 'foo.lock' 'feat/x.lock' '.foo' 'foo.' 'HEAD' '-lead'; do
  code=0
  err=$(bash "$HELPER" --name "$badref" --root "$TEST_TMPDIR/wtroot10c" --repo-dir "$repo" 2>&1 >/dev/null) || code=$?
  assert_exit "git-invalid ref name $badref refused (exit 2, not 4)" 2 "$code"
  assert_contains "git-invalid $badref refusal names the branch grammar" "$err" "not a valid git branch name"
done
# The ref check must not eat stdout: `git check-ref-format --branch` echoes the
# name on success, which would corrupt the sole-stdout-line path contract.
root="$TEST_TMPDIR/wtroot10d"
out=$(bash "$HELPER" --name "feat/refok" --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "ref-valid name still creates (exit 0)" 0 "$?"
assert_eq "ref check leaves stdout as the sole path line" "$root/acme-widget-feat-refok" "$out"
# A valid multi-segment name keeps the branch verbatim but transforms the slug.
root="$TEST_TMPDIR/wtroot10b"
out=$(bash "$HELPER" --name "feat/scope.v2_final-1" --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_eq "valid name: '/' -> '-' in the dir slug" "$root/acme-widget-feat-scope.v2_final-1" "$out"
assert_eq "valid name: branch kept verbatim" "feat/scope.v2_final-1" \
  "$(git -C "$out" rev-parse --abbrev-ref HEAD)"

# --- Case: --repo-dir outside any git repo -> environment error (exit 4) ---
nonrepo="$(mktemp -d "$TEST_TMPDIR/plainXXXXXX")"
bash "$HELPER" --name feat/x --root "$TEST_TMPDIR/wtroot11" --repo-dir "$nonrepo" >/dev/null 2>&1
assert_exit "--repo-dir outside a git repo exits 4" 4 "$?"

# --- Case: a trailing slash on --root does not double the separator ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR/wtroot12"
out=$(bash "$HELPER" --name feat/trail --root "$root/" --repo-dir "$repo" 2>/dev/null)
assert_eq "trailing-slash root yields a single separator" \
  "$root/acme-widget-feat-trail" "$out"

[[ $FAILED -eq 0 ]] || exit 1
