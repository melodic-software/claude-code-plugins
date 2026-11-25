#!/usr/bin/env bash

set -uo pipefail

_WT_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_WT_DIR" == "${BASH_SOURCE[0]}" ]] && _WT_DIR=.
case "$_WT_DIR" in
/* | ?:[/\\]*) HOOK_DIR="$_WT_DIR" ;;
*) HOOK_DIR="$(cd "$_WT_DIR" && pwd)" ;;
esac
# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

gate::refuse() {
  local remedy="$1"
  shift
  printf 'worktree-create-gate: %s\n' "$remedy" >&2
  local line
  for line in "$@"; do
    printf 'worktree-create-gate:   %s\n' "$line" >&2
  done
  exit 1
}

payload=""
if ! hook::buffer_stdin_to payload; then
  gate::refuse \
    'rerun the worktree creation; if it repeats, run with hook debugging on to capture the WorktreeCreate payload' \
    'nothing readable arrived on stdin — the WorktreeCreate payload was empty or could not be buffered' \
    'this is not the same as a payload missing its .name field, which is reported separately'
fi

json_field_to() {
  local __dest="$1" field="$2" value=""
  if command -v jq >/dev/null 2>&1; then
    value=$(printf '%s' "$payload" | jq -r "(.${field} // empty)"' | gsub("\r";"")' 2>/dev/null)
  fi
  if [[ -z "$value" ]]; then
    value=$(printf '%s' "$payload" | sed -n 's/.*"'"$field"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    value="${value%%$'\n'*}"
    value="${value//$'\r'/}"
    value="${value//\\\\/\\}"
  fi
  printf -v "$__dest" '%s' "$value"
}

json_field_to name name
json_field_to repo_dir cwd

if [[ -z "$name" ]]; then
  gate::refuse \
    'name the worktree explicitly (claude --worktree <name>); if a name was supplied, this is a harness defect worth reporting' \
    'the WorktreeCreate payload parsed but carried no .name, and guessing a worktree name is worse than refusing'
fi
repo_dir="${repo_dir:-${CLAUDE_PROJECT_DIR:-$PWD}}"

root="${CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT:-}"
# The single-quoted ${user_config token is matched literally: the unexpanded placeholder is the input.
# shellcheck disable=SC2016
case "$root" in
*'${user_config'*) root="" ;;
*) ;;
esac

helper="$HOOK_DIR/../scripts/worktree-create.sh"
if [[ ! -f "$helper" ]]; then
  gate::refuse \
    'reinstall or update the source-control plugin — its worktree-creation helper is missing from the installed tree' \
    "expected the helper at $helper"
fi

json_field_to session_id session_id
if [[ -n "$session_id" && ! "$session_id" =~ ^[A-Za-z0-9._:-]{1,128}$ ]]; then
  gate::refuse \
    'the WorktreeCreate payload session_id must match ^[A-Za-z0-9._:-]{1,128}$; refusing rather than creating a worktree whose lock no session can claim' \
    "session_id was: $session_id"
fi

args=(--name "$name" --repo-dir "$repo_dir")
if [[ -n "$session_id" ]]; then
  args+=(--session-id "$session_id")
fi
if [[ -n "$root" ]]; then
  args+=(--fallback-root "$root")
fi
data_root="${CLAUDE_PLUGIN_DATA:-}"
if [[ -n "$data_root" ]]; then
  root_file="$(mktemp "${TMPDIR:-/tmp}/worktree-create-gate.XXXXXX")" || {
    gate::refuse \
      'check that TMPDIR points at a writable directory with space free, then retry' \
      'could not create a temp file for the data-root handoff'
  }
  trap 'rm -f "$root_file"' EXIT
  printf '%s' "$data_root" >"$root_file"
  args+=(--data-root-file "$root_file")
fi

path="$(bash "$helper" "${args[@]}")"
status=$?

case "$status" in
0) ;;
2)
  gate::refuse \
    "choose a worktree name git accepts as a branch — no '..', no trailing '.lock', no reserved name like HEAD" \
    "the helper rejected the request as a usage error (exit 2) for name: $name"
  ;;
3)
  gate::refuse \
    'set the worktreeroot.path git config key (git config --global worktreeroot.path <dir>) or the worktree_root plugin option to a directory outside every repository and on the same drive as the repository (Windows), then retry' \
    'the helper refused with exit 3 — no usable external root, a root inside a repository, or a cross-drive root on Windows'
  ;;
4)
  gate::refuse \
    "if the helper named a worktree or session holding the target or its branch, finish there or choose another name; if $repo_dir is not a git repository, there is nothing to isolate: for a background session, set worktree.bgIsolation to \"none\" in settings so it edits in place; --worktree and subagent isolation need a repository" \
    "the helper refused with exit 4: $repo_dir is not a git repository, the target or its branch is held by another worktree or session, or git worktree add itself failed" \
    'the helper or git message above this line is the authoritative detail'
  ;;
*)
  gate::refuse \
    'read the helper output above for the failure, then retry' \
    "the helper exited $status, which is outside its documented 0/2/3/4 taxonomy"
  ;;
esac

if [[ -z "$path" ]]; then
  gate::refuse \
    'reinstall or update the source-control plugin — its worktree-creation helper returned success without a path, which it is never supposed to do' \
    'the helper exited 0 but printed no worktree path, so there is nothing to hand back to Claude Code'
fi

printf '%s\n' "$path"
