#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_EXPORTED_MSYS_PATHCONV_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-exported-msys-pathconv PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

case "${OSTYPE:-}" in
msys* | cygwin* | win32) ;;
*) exit 0 ;;
esac

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq_blocking "guardrails-block-exported-msys-pathconv" "block_exported_msys_pathconv_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || jq_rc=$?
guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"

if [[ "$COMMAND" != *MSYS_NO_PATHCONV* && "$COMMAND" != *MSYS2_ARG_CONV_EXCL* ]]; then
  exit 0
fi

MAX_COMMAND_LEN=16384

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local subject data
  hook::extract_bash_subject_to subject "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$subject" form "$2"
  hook::emit_telemetry "block-exported-msys-pathconv" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block() {
  local form="$1"
  printf '%s\n' \
    'BLOCKED: export of MSYS_NO_PATHCONV / MSYS2_ARG_CONV_EXCL turns off MSYS path conversion for every later command in this string, so git reads a leading / against the current drive.' \
    'Use Windows-native paths, or scope it to one command as a prefix: MSYS_NO_PATHCONV=1 git show "origin/main:.github/workflows/ci.yml".' >&2
  emit_tel "blocked" "$form"
  exit 2
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  block "too-long"
fi

unquote_token_to() {
  local __t="$2"
  __t="${__t#\'}"
  __t="${__t#\"}"
  __t="${__t%\'}"
  __t="${__t%\"}"
  printf -v "$1" '%s' "$__t"
}

token_basename_to() {
  local __b="${2##*/}"
  __b="${__b##*\\}"
  printf -v "$1" '%s' "${__b%.exe}"
}

contains_shell_word() {
  local s="$1" tok base
  local -a tokens=()
  # Intentional word-split of the static matcher subject into tokens.
  # shellcheck disable=SC2206
  tokens=($s)
  for tok in "${tokens[@]}"; do
    unquote_token_to tok "$tok"
    token_basename_to base "$tok"
    case "$base" in
    bash | sh | dash | zsh | ksh | eval) return 0 ;;
    *) ;;
    esac
  done
  return 1
}

is_exported_suppressor() {
  local s="$1" lead nl=$'\n'
  local assign='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
  local name='(MSYS_NO_PATHCONV|MSYS2_ARG_CONV_EXCL)'
  local tail='([=[:space:]\;\|\&]|$)'
  if contains_shell_word "$s"; then
    lead='(^|[^[:alnum:]_.-])'
  else
    lead="(^|[;&|(\`{${nl}])[[:space:]]*"
  fi
  if [[ "$s" =~ ${lead}export[[:space:]]+(--[[:space:]]+)?${assign}${name}${tail} ]]; then
    return 0
  fi
  if [[ "$s" =~ ${lead}(declare|typeset)[[:space:]]+((-[A-Za-z-]+[[:space:]]+)+)${assign}${name}${tail} ]]; then
    [[ "${BASH_REMATCH[3]}" == *x* ]] && return 0
  fi
  return 1
}

leaks_into_child_shell() {
  local s="$1" tok base seen=0
  local -a tokens=()
  # Intentional word-split of the static matcher subject into tokens.
  # shellcheck disable=SC2206
  tokens=($s)
  for tok in "${tokens[@]}"; do
    unquote_token_to tok "$tok"
    if ((seen)); then
      [[ "$tok" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && continue
      token_basename_to base "$tok"
      case "$base" in
      env | command | builtin | exec | nohup | -*) continue ;;
      bash | sh | dash | zsh | ksh) return 0 ;;
      *) seen=0 ;;
      esac
      continue
    fi
    [[ "$tok" == MSYS_NO_PATHCONV=* || "$tok" == MSYS2_ARG_CONV_EXCL=* ]] && seen=1
  done
  return 1
}

if is_exported_suppressor "$COMMAND"; then
  block "export"
fi

if leaks_into_child_shell "$COMMAND"; then
  block "child-shell"
fi

emit_tel "ok" ""
exit 0
