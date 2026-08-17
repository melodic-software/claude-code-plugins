#!/usr/bin/env bash
# Shared helpers for test harnesses that build throwaway git repositories.
# Sourced by repo-level *.test.sh files — not executed directly.
#
# git_test_config wraps git -C with throwaway identity and signing settings.
# git_init_safe refuses to initialize inside the current checkout tree.
#
# ISOLATION (#2840). `git -C <dir>` is a readability guard, not an isolation
# guarantee. `-C` only changes directory, while an exported ABSOLUTE GIT_DIR
# overrides repository DISCOVERY outright, and `git config` writes its default
# --local scope to whatever gitdir finally resolves to. So a suite that
# inherited such an environment writes its FIXTURE identity into the CALLER's
# .git/config and leaves the fixture with no .git at all. Worktrees share the
# main clone's config, so one such leak re-authors commits in every worktree at
# once; a poisoned user.email silently re-authors a commit, which then fails
# this repo's required_signatures rule with `no_user` and cannot be
# force-pushed over.
#
# The exported GIT_DIR behind the real incident came from an ad-hoc tool
# invocation, not from a git hook: this repository has no git hook at any scope
# and core.hooksPath is unset everywhere. The invariant is therefore not "harden
# hooks" but never let a fixture inherit ambient git environment, however it got
# exported.
#
# GIT_CONFIG is cleared alongside the discovery variables and is a DISTINCT leak
# path rather than another spelling of the same one: it does not redirect
# discovery at all, it replaces the file the `git config` subcommand reads and
# writes, so `git -C <fixture> config user.email` lands in whatever file it
# names regardless of -C, of GIT_DIR, and of the working directory. Reproduced
# on git 2.55: with GIT_CONFIG pointing at another repository's config, that
# write set the OTHER repository's user.email and the fixture kept none.
#
# Clearing the inherited git environment is the ONLY thing that isolates, so
# this harness does it once, at source time, for the whole suite that sources
# it. scripts/check-fixture-git-isolation.sh keeps that true.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG

git_test_config() {
  local dir="$1"
  shift
  git -C "$dir" \
    -c user.email=t@t.test \
    -c user.name=test \
    -c commit.gpgsign=false \
    -c core.autocrlf=false \
    "$@"
}

git_init_safe() {
  local dir="$1"
  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "git_init_safe: missing or non-directory path: ${dir:-<empty>}" >&2
    return 1
  fi
  local abs_dir repo_root
  abs_dir="$(cd "$dir" && pwd)"
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
  if [[ -n "$repo_root" ]]; then
    local abs_repo
    abs_repo="$(cd "$repo_root" && pwd)"
    case "$abs_dir" in
      "$abs_repo" | "$abs_repo"/*)
        echo "git_init_safe: refusing path inside current repository: $abs_dir" >&2
        return 1
        ;;
      *)
        ;;
    esac
  fi
  git_test_config "$dir" init -q
}

# Initialize a throwaway repo outside the checkout and give it a local identity.
# Local config on a temp dir cannot leak into the real repository tree.
git_init_test_repo() {
  local dir="$1"
  git_init_safe "$dir" || return 1
  git_test_config "$dir" config user.email t@t.test
  git_test_config "$dir" config user.name test
  git_test_config "$dir" config commit.gpgsign false
  git_test_config "$dir" config core.autocrlf false
}
