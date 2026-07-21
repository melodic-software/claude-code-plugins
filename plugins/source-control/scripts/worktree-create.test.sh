#!/usr/bin/env bash
# Regression tests for worktree-create.sh (issue #399, Phase A).
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

# mkrepo [--origin <url>] — create a fresh git repo fixture with one commit,
# origin/HEAD pointed at the default branch. Echoes the repo path (the sole
# stdout line; all git noise is discarded so command substitution captures only
# the path). Each call gets a unique dir — the function body runs in a
# command-substitution subshell, so a mutating counter would not persist.
mkrepo() {
  local origin_url=""
  [[ "${1:-}" == "--origin" ]] && { origin_url="$2"; shift 2; }
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
      # Point origin/HEAD at main without a network fetch so `fresh` resolves.
      git -C "$repo" update-ref refs/remotes/origin/main "$(git -C "$repo" rev-parse HEAD)"
      git -C "$repo" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
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

[[ $FAILED -eq 0 ]] || exit 1
