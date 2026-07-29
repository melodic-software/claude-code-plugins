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

# TEST_TMPDIR_NATIVE — a drive-letter-anchored form of TEST_TMPDIR on a Windows
# shell (MSYS/Cygwin), used only where a fixture path also carries a
# special shell-metacharacter byte (', $, `). MSYS auto-converts a bare
# POSIX-style argument like /tmp/tmp.a1b2c3 into the real Windows path when it
# invokes a native binary (git.exe) — but that conversion heuristic can miss
# on an argument containing those bytes, and git.exe then treats a leading
# `/` as drive-relative (`C:/tmp/...`), silently landing the worktree
# somewhere other than the printed path. A path that already carries a drive
# letter needs no such conversion, so it never hits the miss. Off Windows
# (no cygpath), TEST_TMPDIR is already a real native path.
if command -v cygpath >/dev/null 2>&1; then
  TEST_TMPDIR_NATIVE="$(cygpath -m "$TEST_TMPDIR")"
else
  TEST_TMPDIR_NATIVE="$TEST_TMPDIR"
fi

# mkrepo [--origin <url>] [--remote-name <name>] [--no-head] — create a fresh git
# repo fixture with one commit; unless --no-head, the remote's HEAD is pointed at
# the default branch. --remote-name names that remote (default `origin`), which
# is what exercises a `git clone -o upstream` clone that has no `origin` at all.
# Echoes the repo path (the sole stdout line; all git noise is discarded so
# command substitution captures only the path). Each call gets a unique dir — the
# function body runs in a command-substitution subshell, so a mutating counter
# would not persist.
mkrepo() {
  local origin_url="" seed_head=1 remote_name="origin"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --origin) origin_url="$2"; shift 2 ;;
      --remote-name) remote_name="$2"; shift 2 ;;
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
      # `--` so an option-shaped remote name is a name, not switches: git accepts
      # one (`git clone -o -foo`), so the fixtures must be able to build one.
      git -C "$repo" remote add -- "$remote_name" "$origin_url"
      if [[ "$seed_head" == 1 ]]; then
        # Point <remote>/HEAD at main without a network fetch so `fresh` resolves.
        git -C "$repo" update-ref "refs/remotes/$remote_name/main" "$(git -C "$repo" rev-parse HEAD)"
        git -C "$repo" symbolic-ref "refs/remotes/$remote_name/HEAD" "refs/remotes/$remote_name/main"
      fi
    fi
  } >/dev/null 2>&1
  printf '%s' "$repo"
}

# addremote <repo> <name> <url> — attach a second remote and seed its HEAD at the
# repo's CURRENT commit, so a caller that commits between calls gives each remote
# a distinguishable tip. Without distinct tips a precedence assertion passes no
# matter which remote the helper picks.
addremote() {
  local repo="$1" name="$2" url="$3"
  {
    git -C "$repo" remote add -- "$name" "$url"
    git -C "$repo" update-ref "refs/remotes/$name/main" "$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" symbolic-ref "refs/remotes/$name/HEAD" "refs/remotes/$name/main"
  } >/dev/null 2>&1
}

# commitfile <repo> <path> — add one commit creating <path>, advancing HEAD past
# whatever remote tips are already seeded.
commitfile() {
  local repo="$1" rel="$2"
  printf 'x\n' > "$repo/$rel"
  {
    git -C "$repo" add "$rel"
    git -C "$repo" commit -qm "add $rel"
  } >/dev/null 2>&1
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
  err=$(bash "$HELPER" --name feat/bs --root "$(cygpath -w "$repo")\\.claude\\worktrees" --repo-dir "$repo" 2>&1 >/dev/null) # portability-ok: Windows path string in a test fixture, not a regex/sed construct
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
  bs_dd="$(cygpath -w "$repo")\\..\\missing\\..\\${repo##*/}\\.claude\\worktrees" # portability-ok: Windows path string in a test fixture, not a regex/sed construct
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
assert_file_exists "base-ref fresh materializes the worktree" "$out/README.md"
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
assert_contains "fresh w/o origin/HEAD names the resolved remote" "$err" "origin/HEAD not set"
assert_file_exists "fresh fallback still creates the worktree" "$root/acme-widget-feat-nohead/README.md"

# --- Case: fresh resolves a sole non-origin remote (`git clone -o upstream`) ---
# The gap this closes: probing only refs/remotes/origin/HEAD misses a repo whose
# single remote is named something else, so `fresh` fell back to local HEAD and
# carried unpushed commits into a supposedly-fresh worktree. The fallback warned,
# but named origin — the one remote such a repo does not have.
repo=$(mkrepo --origin "git@github.com:acme/widget.git" --remote-name upstream)
commitfile "$repo" UNPUSHED.md
root="$TEST_TMPDIR/wtroot-upstream"
out=$(bash "$HELPER" --name feat/upstream-fresh --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "fresh with sole non-origin remote succeeds" 0 "$?"
assert_file_absent "fresh bases on upstream/HEAD, not local HEAD" "$out/UNPUSHED.md"

# --- Case: the uncached-HEAD warning names the RESOLVED remote, not origin ---
# The origin-remote case above cannot prove this: the old hardcoded message
# contained the same substring, so only a non-origin remote discriminates.
repo=$(mkrepo --origin "git@github.com:acme/widget.git" --remote-name upstream --no-head)
root="$TEST_TMPDIR/wtroot-upstream-nohead"
errfile="$TEST_TMPDIR/err-upstream-nohead.txt"
out=$(bash "$HELPER" --name feat/upnohead --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_exit "uncached non-origin HEAD still succeeds" 0 "$?"
assert_contains "warning names the resolved remote's symref" "$(cat "$errfile")" "upstream/HEAD not set"
assert_contains "warning offers set-head for that remote" "$(cat "$errfile")" "set-head upstream --auto"
assert_file_exists "uncached non-origin fallback still creates the worktree" "$out/README.md"

# --- Case: branch.<name>.remote outranks origin when both remotes exist ---
# Three distinct commits so the assertion discriminates all three candidates:
# origin/HEAD (seed), upstream/HEAD (UPSTREAM_ONLY.md), local HEAD (UNPUSHED.md).
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" UPSTREAM_ONLY.md
addremote "$repo" upstream "git@github.com:acme/widget-fork.git"
commitfile "$repo" UNPUSHED.md
git -C "$repo" config branch.main.remote upstream
root="$TEST_TMPDIR/wtroot-branchcfg"
out=$(bash "$HELPER" --name feat/branchcfg --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_file_exists "branch-configured remote wins over origin" "$out/UPSTREAM_ONLY.md"
assert_file_absent "branch-configured remote is not local HEAD" "$out/UNPUSHED.md"

# --- Case: an option-shaped branch-configured remote still outranks origin ---
# `git clone -o -foo <url>` is legal and writes `-foo` into branch.<name>.remote,
# so the rung's existence probe must pass the name after an option terminator.
# Without it git reads `-foo` as switches, the healthy remote is judged missing,
# and resolution falls through to origin — a silently wrong base, not an error.
# `origin` must be present for this to discriminate: with `-foo` as the sole
# remote the sole-remote rung answers correctly whatever rung 1 does.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" DASHED_ONLY.md
addremote "$repo" -foo "git@github.com:acme/widget-fork.git"
commitfile "$repo" UNPUSHED.md
git -C "$repo" config -- branch.main.remote -foo
root="$TEST_TMPDIR/wtroot-dashedremote"
out=$(bash "$HELPER" --name feat/dashedremote --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "option-shaped branch remote still succeeds" 0 "$?"
assert_file_exists "option-shaped branch remote wins over origin" "$out/DASHED_ONLY.md"
assert_file_absent "option-shaped branch remote is not local HEAD" "$out/UNPUSHED.md"

# --- Case: a branch.<name>.remote naming a missing remote falls through to origin ---
# Stale config must not shadow a healthy origin, so the rung requires the name to
# resolve to a remote that actually exists.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" UNPUSHED.md
git -C "$repo" config branch.main.remote ghost
root="$TEST_TMPDIR/wtroot-ghost"
out=$(bash "$HELPER" --name feat/ghost --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "stale branch remote still succeeds" 0 "$?"
# A positive anchor as well: on an empty $out the absent-assertion below would
# probe /UNPUSHED.md and pass no matter how the helper failed.
assert_file_exists "stale branch remote materializes the worktree" "$out/README.md"
assert_file_absent "stale branch remote falls through to origin" "$out/UNPUSHED.md"

# --- Case: branch.<name>.remote = "." (a local-tracking branch) falls through ---
# `.` is git's sentinel for tracking a local branch, not a remote name;
# refs/remotes/./HEAD is nonsense and must never be probed.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" UNPUSHED.md
git -C "$repo" config branch.main.remote .
root="$TEST_TMPDIR/wtroot-dotremote"
out=$(bash "$HELPER" --name feat/dotremote --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "'.' branch remote still succeeds" 0 "$?"
assert_file_exists "'.' branch remote materializes the worktree" "$out/README.md"
assert_file_absent "'.' branch remote falls through to origin" "$out/UNPUSHED.md"

# --- Case: detached HEAD skips the branch rung and still resolves origin ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
commitfile "$repo" UNPUSHED.md
git -C "$repo" checkout -q --detach HEAD
root="$TEST_TMPDIR/wtroot-detached"
out=$(bash "$HELPER" --name feat/detached --root "$root" --base-ref fresh --repo-dir "$repo" 2>/dev/null)
assert_exit "fresh on a detached HEAD succeeds" 0 "$?"
assert_file_absent "detached HEAD still bases on origin/HEAD" "$out/UNPUSHED.md"

# --- Case: several remotes, none named origin, no branch config -> ambiguous ---
# Guessing one remote's default branch would be a silent wrong base, so the
# helper takes the caller-visible HEAD fallback instead.
repo=$(mkrepo --origin "git@github.com:acme/widget.git" --remote-name upstream)
addremote "$repo" fork "git@github.com:someone/widget.git"
root="$TEST_TMPDIR/wtroot-ambiguous"
errfile="$TEST_TMPDIR/err-ambiguous.txt"
out=$(bash "$HELPER" --name feat/ambiguous --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_exit "ambiguous remotes still succeed" 0 "$?"
assert_contains "ambiguous remotes warn about fallback" "$(cat "$errfile")" "could not resolve the remote default branch"
assert_contains "ambiguous remotes name the no-default-remote cause" "$(cat "$errfile")" "no default remote"
assert_file_exists "ambiguous fallback still creates the worktree" "$out/README.md"

# --- Case: a repository with no remotes at all keeps the HEAD fallback ---
repo=$(mkrepo)
root="$TEST_TMPDIR/wtroot-noremote"
errfile="$TEST_TMPDIR/err-noremote.txt"
out=$(bash "$HELPER" --name feat/noremote --root "$root" --base-ref fresh --repo-dir "$repo" 2>"$errfile")
assert_exit "remoteless fresh still succeeds" 0 "$?"
assert_contains "remoteless fresh warns about fallback" "$(cat "$errfile")" "could not resolve the remote default branch"
assert_file_exists "remoteless fallback still creates the worktree" "$out/README.md"

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
# `check-ref-format --branch` takes a branchname-shorthand, so it does repository
# discovery and dies when the process CWD is a stale checkout (a .git file naming
# a gitdir that no longer exists). Scoping it to $toplevel keeps a VALID name from
# being rejected because of where the caller happened to stand — the documented
# invocation omits --repo-dir, so the CWD is the default.
stale="$(mktemp -d "$TEST_TMPDIR/staleXXXXXX")"
printf 'gitdir: %s/definitely-not-here\n' "$TEST_TMPDIR" > "$stale/.git"
root="$TEST_TMPDIR/wtroot10e"
out=$(cd "$stale" && bash "$HELPER" --name "feat/cwdok" --root "$root" --repo-dir "$repo" 2>/dev/null)
assert_exit "valid name unaffected by a stale .git in the CWD (exit 0)" 0 "$?"
assert_eq "stale-CWD run still prints the worktree path" "$root/acme-widget-feat-cwdok" "$out"
# ...and an invalid name is still caught from that same stale CWD.
code=0
(cd "$stale" && bash "$HELPER" --name 'feat/foo..bar' --root "$TEST_TMPDIR/wtroot10f" --repo-dir "$repo") >/dev/null 2>&1 || code=$?
assert_exit "stale CWD still rejects a git-invalid name (exit 2)" 2 "$code"
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

# --- Case: --root and --root-file together are a usage error (exit 2) ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-both"
printf '%s' "$TEST_TMPDIR/wtroot-both" > "$root_file"
bash "$HELPER" --name feat/both --root "$TEST_TMPDIR/wtroot-both" --root-file "$root_file" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root and --root-file together exit 2" 2 "$?"

# --- Case: an EMPTY value does not make a supplied flag count as absent ---
# The exclusion keys off whether each flag appeared, not whether its value is
# non-empty; otherwise `--root ''` would let --root-file quietly win (and vice
# versa) despite the caller naming two sources.
bash "$HELPER" --name feat/both2 --root "" --root-file "$root_file" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root '' with --root-file still exits 2" 2 "$?"
bash "$HELPER" --name feat/both3 --root "$TEST_TMPDIR/wtroot-both" --root-file "" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root with --root-file '' still exits 2" 2 "$?"

# --- Case: --root-file pointing at a missing file is a usage error (exit 2) ---
bash "$HELPER" --name feat/missingfile --root-file "$TEST_TMPDIR/does-not-exist" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root-file missing file exit 2" 2 "$?"

# --- Case: --root-file carries a special-character root safely (exit 0) ---
# This is the out-of-band handoff the skill uses: ${user_config.worktree_root}
# substitution into skill markdown is raw text, not shell-escaped, so a root
# containing a single quote, `$`, or a backtick would break an inline --root
# shell literal. --root-file sidesteps that entirely — the value never passes
# through a shell literal we write; the file's bytes ARE the root.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR_NATIVE/wtroot13-O'Connor \$weird \`root\`"
root_file="$TEST_TMPDIR/rootfile-special"
printf '%s' "$root" > "$root_file"
out=$(bash "$HELPER" --name feat/special --root-file "$root_file" --repo-dir "$repo" 2>/dev/null)
assert_exit "--root-file special-char root creates (exit 0)" 0 "$?"
assert_eq "--root-file special-char root computes the exact path" \
  "$root/acme-widget-feat-special" "$out"
assert_file_exists "--root-file special-char worktree materialized" "$out/README.md"

# --- Case: --root-file with empty content refuses exit 3 (reuses the unset guard) ---
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-empty"
: > "$root_file"
err=$(bash "$HELPER" --name feat/empty --root-file "$root_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "--root-file empty content refuses exit 3" 3 "$?"
assert_contains "--root-file empty content names worktree_root key" "$err" "worktree_root"

# --- Case: --root-file holding the literal unexpanded token refuses exit 3 ---
# When the key is unset the caller writes ${user_config.worktree_root} verbatim
# — same literal-token detection the existing --root path already covers, now
# reached through the file.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-token"
# shellcheck disable=SC2016
printf '%s' '${user_config.worktree_root}' > "$root_file"
bash "$HELPER" --name feat/token --root-file "$root_file" --repo-dir "$repo" >/dev/null 2>&1
assert_exit "--root-file unexpanded token refuses exit 3" 3 "$?"

# --- Case: a root whose last byte is significant survives intact (exit 0) ---
# The file's bytes ARE the root, so nothing is stripped from the end. A trailing
# dot would vanish under any "strip the terminator" reader that guessed wrong.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root="$TEST_TMPDIR_NATIVE/wtroot14-noeol.d"
root_file="$TEST_TMPDIR/rootfile-noeol"
printf '%s' "$root" > "$root_file"
out=$(bash "$HELPER" --name feat/noeol --root-file "$root_file" --repo-dir "$repo" 2>/dev/null)
assert_exit "--root-file unterminated value creates (exit 0)" 0 "$?"
assert_eq "--root-file unterminated value keeps every byte" "$root/acme-widget-feat-noeol" "$out"
assert_file_exists "--root-file unterminated value materialized" "$out/README.md"

# --- Case: --root-file holding an embedded newline is a usage error (exit 2) ---
# A newline inside worktree_root is never a valid root. Taking only the first
# line would silently proceed with a root the caller never asked for, and the
# second line here is exactly the payload a heredoc-delimiter collision would
# have smuggled into shell source — which is why the handoff is non-shell now.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-multiline"
printf '%s\n%s\n' "$TEST_TMPDIR/wtroot15-multi" "touch $TEST_TMPDIR/pwned" > "$root_file"
err=$(bash "$HELPER" --name feat/multi --root-file "$root_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "--root-file embedded newline is a usage error (exit 2)" 2 "$?"
assert_contains "--root-file newline error names the newline" "$err" "newline"
assert_file_absent "--root-file newline payload never executed" "$TEST_TMPDIR/pwned"

# --- Case: a TRAILING newline is rejected too, not trimmed (exit 2) ---
# Trimming one terminator is a guess: it is indistinguishable from a root whose
# own last byte is a newline, and guessing wrong silently creates the worktree
# somewhere the caller never named. The handoff writes the value unterminated,
# so a trailing newline means the value really carries one.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-trailing-eol"
printf '%s\n' "$TEST_TMPDIR/wtroot16-trailing" > "$root_file"
err=$(bash "$HELPER" --name feat/trailing --root-file "$root_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "--root-file trailing newline is a usage error (exit 2)" 2 "$?"
assert_contains "--root-file trailing-newline error names the newline" "$err" "newline"
assert_file_absent "--root-file trailing-newline root never materialized" \
  "$TEST_TMPDIR/wtroot16-trailing/acme-widget-feat-trailing/README.md"

# --- Case: a NUL byte in the root file is a usage error (exit 2) ---
# Command substitution DROPS NUL bytes, so `<root>-<NUL>suffix` would silently
# collapse to `<root>-suffix` and create a worktree at a path nobody supplied.
# The check therefore runs on the file, before the value reaches a variable.
repo=$(mkrepo --origin "git@github.com:acme/widget.git")
root_file="$TEST_TMPDIR/rootfile-nul"
printf '%s\000%s' "$TEST_TMPDIR/wtroot17-nul" "suffix" > "$root_file"
err=$(bash "$HELPER" --name feat/nul --root-file "$root_file" --repo-dir "$repo" 2>&1 >/dev/null)
assert_exit "--root-file NUL byte is a usage error (exit 2)" 2 "$?"
assert_contains "--root-file NUL error names the NUL byte" "$err" "NUL"
assert_file_absent "--root-file NUL-collapsed path never materialized" \
  "$TEST_TMPDIR/wtroot17-nulsuffix/acme-widget-feat-nul/README.md"

[[ $FAILED -eq 0 ]] || exit 1
