#!/usr/bin/env bash
# GENERATED from lib/worktree-root-resolve.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
#   exit 0 (including unset), 2 usage

WORKTREE_ROOT_CURRENT_KEY="worktreeroot.path"

# shellcheck source=worktree-root-legacy.sh
source "${BASH_SOURCE[0]%/*}/worktree-root-legacy.sh"

worktree_root_git() {
  if declare -F _worktree_root_git >/dev/null 2>&1; then
    _worktree_root_git "$@"
  elif declare -F hook::git_untrusted >/dev/null 2>&1; then
    hook::git_untrusted "$@"
  else
    command git "$@"
  fi
}

worktree_root_last_raw() {
  local repo="$1" key="$2" last="" had=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    last="$line"
    had=1
  done < <(worktree_root_git -C "$repo" config --get-all --type=path "$key" 2>/dev/null)
  ((had)) || return 1
  printf '%s' "$last"
  return 0
}

worktree_root_resolve() {
  local repo="$1" raw=""
  export WORKTREE_ROOT_VALUE=""
  export WORKTREE_ROOT_KEY_USED=""
  [[ -n "$repo" ]] || return 1
  worktree_root_git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 1

  if raw=$(worktree_root_last_raw "$repo" "$WORKTREE_ROOT_CURRENT_KEY") &&
    [[ -n "$raw" ]]; then
    worktree_root_legacy_retire "$repo"
  elif [[ -n "${WORKTREE_ROOT_LEGACY_KEY:-}" ]] &&
    raw=$(worktree_root_last_raw "$repo" "$WORKTREE_ROOT_LEGACY_KEY") &&
    [[ -n "$raw" ]]; then
    worktree_root_legacy_promote "$repo" || true
  else
    return 1
  fi
  WORKTREE_ROOT_VALUE="$raw"
  WORKTREE_ROOT_KEY_USED="$WORKTREE_ROOT_CURRENT_KEY"
  return 0
}

worktree_root_resolve_main() {
  local repo_dir="."
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --repo-dir)
      [[ $# -ge 2 ]] || {
        printf 'worktree-root-resolve.sh: --repo-dir requires a value\n' >&2
        return 2
      }
      repo_dir="$2"
      shift 2
      ;;
    -h | --help)
      printf '%s\n' "worktree-root-resolve.sh --repo-dir <dir>"
      return 0
      ;;
    *)
      printf 'worktree-root-resolve.sh: unknown argument: %s\n' "$1" >&2
      return 2
      ;;
    esac
  done
  if worktree_root_resolve "$repo_dir"; then
    printf '%s\n' "$WORKTREE_ROOT_VALUE"
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  worktree_root_resolve_main "$@"
fi
