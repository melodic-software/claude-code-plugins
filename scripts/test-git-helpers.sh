#!/usr/bin/env bash
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

if [[ -d ${TMPDIR:-} ]] && git -C "$TMPDIR" rev-parse --git-dir >/dev/null 2>&1; then
  echo "test-git-helpers: refusing TMPDIR inside a git repository: $TMPDIR" >&2
  exit 2
fi

git_test_config() {
  local dir="$1"
  shift
  if [[ -z "$dir" ]] || [[ "${1:-}" != init && "${1:-}" != clone && ! -e "$dir/.git" && ! -f "$dir/HEAD" ]]; then
    echo "git_test_config: refusing a path that is not a repository root: ${dir:-<empty>}" >&2
    return 1
  fi
  git -C "$dir" \
    -c user.email=t@t.test \
    -c user.name=test \
    -c commit.gpgsign=false \
    -c tag.gpgsign=false \
    -c core.autocrlf=false \
    -c gc.auto=0 \
    -c maintenance.auto=false \
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
    if [[ "$abs_dir" == "$abs_repo" || "$abs_dir" == "$abs_repo"/* ]]; then
      echo "git_init_safe: refusing path inside current repository: $abs_dir" >&2
      return 1
    fi
  fi
  git_test_config "$dir" init -q
}

git_init_test_repo() {
  local dir="$1"
  git_init_safe "$dir" || return 1
  git_test_config "$dir" config user.email t@t.test
  git_test_config "$dir" config user.name test
  git_test_config "$dir" config commit.gpgsign false
  git_test_config "$dir" config tag.gpgsign false
  git_test_config "$dir" config core.autocrlf false
}
