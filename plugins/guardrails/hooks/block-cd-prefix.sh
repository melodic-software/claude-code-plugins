#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_CD_PREFIX_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-cd-prefix PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70

hook::buffer_stdin_to INPUT || exit 0

[[ "$INPUT" == *'cd '* || "$INPUT" == *'cd\t'* ]] || exit 0

hook::require jq "PreToolUse" guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || exit 0
((HOOK_JQ_FIELDS_NUL)) && exit 0

CDP_COMMAND="${HOOK_JQ_FIELDS[0]}"
CDP_TOOL="${HOOK_JQ_FIELDS[1]:-Bash}"
CDP_CWD="${HOOK_JQ_FIELDS[2]}"
[[ "$CDP_TOOL" == Bash && -n "$CDP_COMMAND" ]] || exit 0

CDP_NL=$'\n'
CDP_PREFIX_RE="^[[:space:]]*cd[[:space:]]+(\"[^\"]*\"|'[^']*'|[^[:space:];&|<>()\"']+)[[:space:]]*(&&|;|${CDP_NL})"
[[ "$CDP_COMMAND" =~ $CDP_PREFIX_RE ]] || exit 0

cdp::norm_to() {
  local __p="${2//\\//}"
  while [[ "$__p" == */ && "$__p" != / ]]; do __p="${__p%/}"; done
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    __p="${__p,,}"
    [[ "$__p" =~ ^/([a-z])(/.*)?$ ]] && __p="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    ;;
  *) ;;
  esac
  printf -v "$1" '%s' "$__p"
}

# shellcheck disable=SC2329  # invoked by the parse callback below
cdp::relative_target() {
  case "$2" in
  '' | /* | '~'* | '$'* | \\* | [A-Za-z]:*) return 1 ;;
  *) ;;
  esac
  [[ "$1" == '>&' && "$2" =~ ^([0-9]+|-)$ ]] && return 1
  return 0
}

CDP_SEG=0
CDP_DIR=""
CDP_HIT=""
# shellcheck disable=SC2329  # invoked by hook::bash_parse_segments
cdp::segment() {
  CDP_SEG=$((CDP_SEG + 1))
  if ((CDP_SEG == 1)); then
    (($# == 2)) && [[ "$1" == cd ]] && CDP_DIR="$2"
    return 0
  fi
  [[ -n "$CDP_DIR" && "$CDP_HIT" != git ]] || return 0
  local w i
  for w in "$@"; do
    [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue
    w="${w##*/}"
    w="${w##*\\}"
    [[ "${w%.exe}" == git ]] && CDP_HIT=git
    break
  done
  for ((i = 0; i < ${#HOOK_SEG_REDIR_OP[@]}; i++)); do
    case "${HOOK_SEG_REDIR_OP[i]}" in
    '>' | '>>' | '<>' | '>&') ;;
    *) continue ;;
    esac
    [[ "${HOOK_SEG_REDIR_OPAQUE[i]-0}" == 1 ]] && continue
    cdp::relative_target "${HOOK_SEG_REDIR_OP[i]}" "${HOOK_SEG_REDIR_TARGET[i]-}" && CDP_HIT="${CDP_HIT:-redirect}"
  done
  return 0
}

hook::bash_parse_segments "$CDP_COMMAND" cdp::segment
[[ -n "$CDP_DIR" && -n "$CDP_HIT" ]] || exit 0

CDP_DIR_N=""
CDP_CWD_N=""
cdp::norm_to CDP_DIR_N "$CDP_DIR"
[[ "$CDP_DIR_N" == . ]] && exit 0
if [[ -n "$CDP_CWD" ]]; then
  cdp::norm_to CDP_CWD_N "$CDP_CWD"
  [[ "$CDP_DIR_N" == "$CDP_CWD_N" ]] && exit 0
fi

# shellcheck disable=SC2016  # the backticks are literal text in the reasons
if [[ "$CDP_HIT" == git ]]; then
  echo 'BLOCKED: Run `git -C <abs path> ...` with absolute paths instead of `cd`; for a multi-line commit message, Write the message to a file and use `git commit -F <file>`.' >&2
else
  echo 'BLOCKED: Write to an absolute path, and run the command with its own directory option (for example `make -C <abs path>`) or an absolute path instead of `cd`.' >&2
fi
exit 2
