#!/usr/bin/env bash
# Shared helpers for test harnesses that build throwaway git repositories.
# Sourced by repo-level *.test.sh files — not executed directly.
#
# git_test_config wraps git -C with throwaway identity and signing settings so
# nothing is persisted into a repository's .git/config. git_init_safe refuses
# to initialize inside the current checkout tree.

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
