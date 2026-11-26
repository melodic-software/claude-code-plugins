#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_FOREGROUND_WAIT_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-foreground-wait PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

hook::buffer_stdin_to INPUT || exit 0

[[ "$INPUT" == *until* || "$INPUT" == *--watch* ]] || exit 0

hook::require jq "PreToolUse" guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || exit 0
((HOOK_JQ_FIELDS_NUL)) && exit 0

FWG_COMMAND="${HOOK_JQ_FIELDS[0]}"
FWG_TOOL="${HOOK_JQ_FIELDS[1]:-Bash}"
[[ "$FWG_TOOL" == Bash && -n "$FWG_COMMAND" ]] || exit 0

FWG_NL=$'\n'
FWG_UNTIL_RE="(^|[;&|(){}!]|${FWG_NL}|(^|[^[:alnum:]_.-])(do|then|else|elif|if|while|time))[[:space:]]*until[[:space:]]"
FWG_UNTIL=0
FWG_WATCH=0
[[ "$FWG_COMMAND" =~ $FWG_UNTIL_RE ]] && FWG_UNTIL=1
[[ "$FWG_COMMAND" == *--watch* ]] && FWG_WATCH=1
((FWG_UNTIL || FWG_WATCH)) || exit 0

hook::jq_fields "$INPUT" '.tool_input.run_in_background' || exit 0
[[ "${HOOK_JQ_FIELDS[0]-}" == true ]] && exit 0

FWG_HIT=""
IFS=',' read -ra FWG_RUNNERS <<<"${CLAUDE_PLUGIN_OPTION_BLOCK_FOREGROUND_WAIT_SCRIPT_RUNNERS-npm,pnpm,yarn,bun,npx}"
# The parse callback: a `--watch` argument in a segment that runs a program.
# shellcheck disable=SC2329  # invoked by hook::bash_parse_segments
fwg::segment() {
  ((FWG_WATCH)) && [[ -z "$FWG_HIT" ]] || return 0
  local -a words=("$@")
  local i=0 n=$# cmd r forwards=0
  while ((i < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do ((i++)); done
  ((i < n)) || return 0
  cmd="${words[i]##*/}"
  case "$cmd" in
  echo | printf) return 0 ;;
  *) ;;
  esac
  for r in ${FWG_RUNNERS[@]+"${FWG_RUNNERS[@]}"}; do
    [[ "${r// /}" == "$cmd" ]] && forwards=1
  done
  for ((i++; i < n; i++)); do
    [[ "${HOOK_SEG_WORD_QUOTED[i]-0}" == 0 ]] || continue
    case "${words[i]}" in
    --) ((forwards)) || return 0 ;;
    --watch)
      FWG_HIT=watch
      return 0
      ;;
    *) ;;
    esac
  done
  return 0
}

hook::bash_parse_segments "$FWG_COMMAND" fwg::segment

# shellcheck disable=SC2329  # invoked through hook::_c_locale
fwg::bare_text() {
  local e s t at=0 text="" rest out="" c
  for e in ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}; do
    s="${e%% *}"
    e="${e#* }"
    t="${e%% *}"
    ((s < at)) && continue
    text+="${FWG_COMMAND:at:s-at}${FWG_NL}"
    at=$t
  done
  rest="$text${FWG_COMMAND:at}"
  local plain_re="^([^\"'#\\\\]*)([\"'#\\\\])(.*)$" dq_re="^([^\"\\\\]*)(\\\\.|\")(.*)$"
  local ansi_re="^([^'\\\\]*)(\\\\.|')(.*)$" cmt_re='[[:space:];&|()]$'
  while [[ "$rest" =~ $plain_re ]]; do
    out+="${BASH_REMATCH[1]}"
    c="${BASH_REMATCH[2]}"
    rest="${BASH_REMATCH[3]}"
    case "$c" in
    "'")
      if [[ "$out" == *'$' ]]; then
        while [[ "$rest" =~ $ansi_re ]]; do
          rest="${BASH_REMATCH[3]}"
          [[ "${BASH_REMATCH[2]}" == "'" ]] && break
        done
      elif [[ "$rest" == *"'"* ]]; then
        rest="${rest#*\'}"
      fi
      out+=Q
      ;;
    '"')
      while [[ "$rest" =~ $dq_re ]]; do
        rest="${BASH_REMATCH[3]}"
        [[ "${BASH_REMATCH[2]}" == '"' ]] && break
      done
      out+=Q
      ;;
    \\)
      rest="${rest:1}"
      out+=Q
      ;;
    '#')
      if [[ -z "$out" || "$out" =~ $cmt_re ]]; then
        if [[ "$rest" == *"$FWG_NL"* ]]; then rest="${rest#*"$FWG_NL"}"; else rest=""; fi
        out+="$FWG_NL"
      else
        out+='#'
      fi
      ;;
    *) ;;
    esac
  done
  FWG_BARE="$out$rest"
}

FWG_BARE=""
if [[ -z "$FWG_HIT" ]] && ((FWG_UNTIL)); then
  hook::_c_locale fwg::bare_text
  [[ "$FWG_BARE" =~ $FWG_UNTIL_RE ]] && FWG_HIT=until
fi
[[ -n "$FWG_HIT" ]] || exit 0

# shellcheck disable=SC2016  # the backticks are literal text in the reasons
if [[ "$FWG_HIT" == until ]]; then
  echo 'BLOCKED: This `until` loop waits in the foreground. Run the command with run_in_background set to true, or watch it with the Monitor tool, and read the result when it finishes.' >&2
else
  echo 'BLOCKED: This `--watch` command waits in the foreground. Run it with run_in_background set to true, or watch it with the Monitor tool, and read the result when it finishes.' >&2
fi
exit 2
