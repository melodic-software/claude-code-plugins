#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_WORKTREE_ADD_CONTAINMENT_GATE_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=worktree-path-lib.sh
source "$HOOK_DIR/worktree-path-lib.sh"
# shellcheck source=../scripts/worktree-root-resolve.sh
source "$HOOK_DIR/../scripts/worktree-root-resolve.sh"
hook::buffer_stdin_to INPUT || exit 0

hook::require jq "PreToolUse" "source-control" "$INPUT"

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
COMMAND="${COMMAND//$'\r'/}"
[[ -n "$COMMAND" ]] || exit 0
[[ "$COMMAND" =~ (^|[^[:alnum:]_.-])[Gg][Ii][Tt][^[:alnum:]_-] ]] || exit 0
[[ "$COMMAND" == *worktree* ]] || exit 0
[[ "$COMMAND" == *add* ]] || exit 0

HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
HOOK_CWD="${HOOK_CWD//$'\r'/}"

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
git_unlocated() {
  (
    unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES \
      GIT_DISCOVERY_ACROSS_FILESYSTEM
    git --no-pager -c core.fsmonitor=false -c core.hooksPath=/dev/null "$@"
  ) 2>/dev/null
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
repo_enclosing() {
  local target="$1" probe parent top inside gitdir
  probe="${target%/*}"
  [[ -n "$probe" ]] || probe="/"
  while [[ ! -e "$probe" ]]; do
    parent="${probe%/*}"
    [[ "$parent" == "$probe" || -z "$parent" ]] && break
    probe="$parent"
  done
  [[ -e "$probe" ]] || return 1
  top=$(git_unlocated -C "$probe" rev-parse --show-toplevel)
  top="${top//$'\r'/}"
  if [[ -n "$top" ]]; then
    printf 'a git working tree\n%s' "$top"
    return 0
  fi
  inside=$(git_unlocated -C "$probe" rev-parse --is-inside-git-dir)
  if [[ "${inside//$'\r'/}" == "true" ]]; then
    gitdir=$(git_unlocated -C "$probe" rev-parse --absolute-git-dir)
    printf 'a git directory\n%s' "${gitdir//$'\r'/}"
    return 0
  fi
  return 1
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
configured_root() {
  local hint="$1" r=""
  if [[ -n "$hint" ]]; then
    WORKTREE_ROOT_SKIP_RETIRE=1 worktree_root_resolve "$hint" || true
    r="${WORKTREE_ROOT_VALUE:-}"
  fi
  if [[ -z "$r" ]]; then
    r="${CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT:-}"
    # shellcheck disable=SC2016  # the single-quoted token is matched literally
    [[ "$r" == *'${user_config'* ]] && r=""
  fi
  if [[ -z "$r" && -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    r="${CLAUDE_PLUGIN_DATA%/}/worktrees"
  fi
  printf '%s' "$r"
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
block() {
  local target="$1" kind="$2" detail="$3" hint="$4" root
  root=$(configured_root "$hint")
  local msg="BLOCKED: git worktree add target $target is inside $kind $detail."
  if [[ -n "$root" ]]; then
    msg+=" Add it under $root instead, e.g. git worktree add \"$root/<owner>-<repo>-<slug>\" ..., or use /source-control:worktree create."
  else
    msg+=" No external worktree root is configured; ask the user to set one (git config --global worktreeroot.path <dir-outside-every-repo>), or use /source-control:worktree create."
  fi
  echo "$msg" >&2
  exit 2
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local abs verdict kind detail
  # shellcheck disable=SC2310  # the return status IS the verdict; abs is read only on 0
  worktree_add_target_to abs check_segment "$HOOK_CWD" "$@" || return 0

  # shellcheck disable=SC2310  # the return status IS the verdict; output is read only on 0
  if verdict=$(repo_enclosing "$abs"); then
    kind="${verdict%%$'\n'*}"
    detail="${verdict#*$'\n'}"
    block "$abs" "$kind" "$detail" "$WORKTREE_ADD_BASE"
  fi
  return 0
}

hook::bash_parse_segments "$COMMAND" check_segment

exit 0
