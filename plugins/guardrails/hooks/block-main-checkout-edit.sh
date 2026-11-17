#!/usr/bin/env bash
# PreToolUse guard on Write, Edit and NotebookEdit: what it denies, what passes and its limits are
# in https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/guardrails/README.md#the-guards
# (block-main-checkout-edit); every check before `git check-ignore` uses bash builtins only, per
# https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/hook-budget/README.md

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_MAIN_CHECKOUT_EDIT_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-main-checkout-edit PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70

hook::buffer_stdin_to INPUT || exit 0
hook::require jq "PreToolUse" guardrails "$INPUT"
hook::jq_fields "$INPUT" '.tool_name' '.tool_input.file_path' '.tool_input.notebook_path' || exit 0
((HOOK_JQ_FIELDS_NUL)) && exit 0

case "${HOOK_JQ_FIELDS[0]}" in
Write | Edit | NotebookEdit) ;;
*) exit 0 ;;
esac
MCE_PATH="${HOOK_JQ_FIELDS[1]:-${HOOK_JQ_FIELDS[2]}}"
MCE_PATH="${MCE_PATH//\\//}"
case "$MCE_PATH" in
/* | [A-Za-z]:/*) ;;
*) exit 0 ;;
esac
[[ "$MCE_PATH/" == */.git/* ]] && exit 0

mce::first_line_to() {
  local __l=""
  [[ -f "$2" && -r "$2" ]] || return 1
  IFS= read -r __l <"$2" || [[ -n "$__l" ]] || return 1
  printf -v "$1" '%s' "${__l%$'\r'}"
}

MCE_ROOT="${MCE_PATH%/*}"
until [[ -e "$MCE_ROOT/.git" ]]; do
  [[ "$MCE_ROOT" == */* && -n "${MCE_ROOT%/*}" ]] || exit 0
  MCE_ROOT="${MCE_ROOT%/*}"
done

if [[ -d "$MCE_ROOT/.git" ]]; then
  MCE_GITDIR="$MCE_ROOT/.git"
else
  mce::first_line_to MCE_LINE "$MCE_ROOT/.git" || exit 0
  [[ "$MCE_LINE" == "gitdir: "* ]] || exit 0
  MCE_GITDIR="${MCE_LINE#gitdir: }"
  case "$MCE_GITDIR" in
  /* | [A-Za-z]:/*) ;;
  *) MCE_GITDIR="$MCE_ROOT/$MCE_GITDIR" ;;
  esac
  [[ -e "$MCE_GITDIR/commondir" ]] && exit 0
fi

mce::git() { GIT_DIR="$MCE_GITDIR" GIT_WORK_TREE="$MCE_ROOT" git -C "$MCE_ROOT" "$@"; }

mce::symref_to() {
  local __v=""
  if [[ -d "$MCE_GITDIR/reftable" ]]; then
    __v=$(mce::git symbolic-ref -q "$2" 2>/dev/null) || return 1
  else
    mce::first_line_to __v "$MCE_GITDIR/$2" || return 1
    [[ "$__v" == "ref: "* ]] || return 1
    __v="${__v#ref: }"
  fi
  printf -v "$1" '%s' "$__v"
}

MCE_HEAD="" MCE_DEFAULT=""
mce::symref_to MCE_HEAD HEAD || exit 0
[[ "$MCE_HEAD" == refs/heads/* ]] || exit 0
MCE_BRANCH="${MCE_HEAD#refs/heads/}"

if ! mce::symref_to MCE_DEFAULT refs/remotes/origin/HEAD; then
  [[ -f "$MCE_GITDIR/config" ]] || exit 0
  while IFS= read -r MCE_LINE; do
    if [[ "${MCE_LINE%$'\r'}" =~ ^[[:space:]]*\[remote[[:space:]]+\"origin\"\] ]]; then
      printf 'guardrails: %s has an origin remote but no origin/HEAD, so block-main-checkout-edit cannot tell its default branch and allows this edit. Set it with: git -C %s remote set-head origin --auto\n' \
        "$MCE_ROOT" "$MCE_ROOT" >&2
      break
    fi
  done <"$MCE_GITDIR/config"
  exit 0
fi
[[ "$MCE_BRANCH" == "${MCE_DEFAULT#refs/remotes/origin/}" ]] || exit 0

MCE_REL="${MCE_PATH#"$MCE_ROOT"/}"
mce::git check-ignore -q -- "$MCE_REL" 2>/dev/null
(($? == 1)) || exit 0

MCE_REPO="${MCE_ROOT##*/}"
printf '%s\n' \
  "BLOCKED: $MCE_PATH is in the main checkout of $MCE_ROOT, on its default branch $MCE_BRANCH. Make this edit in a worktree instead, so the main checkout stays on $MCE_BRANCH for every session:" \
  "1. Read $MCE_ROOT/AGENTS.md (else CLAUDE.md) for this repository's worktree convention; where it differs from the steps below, it wins." \
  "2. If someone can approve EnterWorktree, run \`/source-control:worktree create <short-name>\`. In a background or headless session, run \`git -C $MCE_ROOT worktree add <worktree root>/$MCE_REPO-<short-name> -b <type>/<short-name> origin/$MCE_BRANCH\` and do not enter it." \
  "3. Repeat this edit in the worktree by absolute path: <worktree>/$MCE_REL" \
  "Git-ignored paths in the main checkout are allowed." >&2
exit 2
