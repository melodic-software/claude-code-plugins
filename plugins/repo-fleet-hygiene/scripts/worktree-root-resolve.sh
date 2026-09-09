#!/usr/bin/env bash
# worktree-root-resolve.sh — last-wins read of worktreeroot.path.
# Owner: reference/worktree-root-convention.md (source-control).
#
# Git-config(1) Variables invites third-party keys that do not collide with
# Git or popular tools. Git owns worktree.*; git-wt owns wt.basedir. This
# capability section is the collision-free spelling.
#
# A retired alias peel (auto-rewrite onto this key, then drop) lives in
# worktree-root-legacy.sh and is deleted after 2026-12-31.
#
# Sourced or executed. When executed:
#   worktree-root-resolve.sh --repo-dir <dir>
#   stdout: the path (one line) or empty
#   exit 0 (including unset), 2 usage
#
# When sourced, call worktree_root_resolve <repo-dir>
#   returns 0 and sets WORKTREE_ROOT_VALUE / WORKTREE_ROOT_KEY_USED
#   returns 1 if no key yields a non-empty last value
#   KEY_USED is always the current key when a value is returned
#
# Git invocation: _worktree_root_git if that function is defined (the
# fleet-audit allowlist wrapper), else git. No scope flag: includes stay on.

WORKTREE_ROOT_CURRENT_KEY="worktreeroot.path"

# Command-substitution `$(cd && pwd)` would add a fork on every source, including
# the containment-gate hot path. Keep the same `%/*` form the other callers use.
# shellcheck source=worktree-root-legacy.sh
source "${BASH_SOURCE[0]%/*}/worktree-root-legacy.sh"

worktree_root_git() {
  if declare -F _worktree_root_git >/dev/null 2>&1; then
    _worktree_root_git "$@"
  else
    command git "$@"
  fi
}

# Last record of --get-all --type=path, including a blank last record.
# Prints that record (possibly empty) and returns 0 when the key had at
# least one value; returns 1 when the key is unset.
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

# Sets WORKTREE_ROOT_VALUE and WORKTREE_ROOT_KEY_USED. Empty last value on a
# key is not usable: try the next key (matching create.sh falling through
# when tail -n 1 is blank). A retired-alias hit is rewritten onto the current
# key at the winning origin unless the git wrapper is read-only.
worktree_root_resolve() {
  local repo="$1" raw=""
  # Exported: sourced callers (create, doctor, containment, fleet audit) read these.
  export WORKTREE_ROOT_VALUE=""
  export WORKTREE_ROOT_KEY_USED=""
  [[ -n "$repo" ]] || return 1
  worktree_root_git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || return 1

  if raw=$(worktree_root_last_raw "$repo" "$WORKTREE_ROOT_CURRENT_KEY") &&
    [[ -n "$raw" ]]; then
    WORKTREE_ROOT_VALUE="$raw"
    WORKTREE_ROOT_KEY_USED="$WORKTREE_ROOT_CURRENT_KEY"
    worktree_root_legacy_retire "$repo"
    return 0
  fi
  if [[ -n "${WORKTREE_ROOT_LEGACY_KEY:-}" ]] &&
    raw=$(worktree_root_last_raw "$repo" "$WORKTREE_ROOT_LEGACY_KEY") &&
    [[ -n "$raw" ]]; then
    WORKTREE_ROOT_VALUE="$raw"
    WORKTREE_ROOT_KEY_USED="$WORKTREE_ROOT_CURRENT_KEY"
    worktree_root_legacy_promote "$repo" || true
    return 0
  fi
  return 1
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
