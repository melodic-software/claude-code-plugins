#!/usr/bin/env bash
# PreToolUse hook: deny a foreground Bash call that waits with an `until` loop
# or a `--watch` flag, with the reason to run it in the background or watch it
# with a monitor.
#
# A foreground wait holds the session until the wait ends. The Bash tool input
# carries `run_in_background` (hooks reference, "PreToolUse input" > "Bash",
# https://code.claude.com/docs/en/hooks), so a background call is told apart
# from a foreground one and passes.
#
# MATCHED, on the Bash tool when `run_in_background` is not true:
#   - an `until` keyword where a command starts: at the start, or after `;`,
#     `&`, `|`, `(`, `)`, `{`, `}`, `!`, a newline, or the word `do`, `then`,
#     `else`, `elif`, `if`, `while` or `time`, outside quotes, comments and
#     heredoc bodies;
#   - an unquoted `--watch` argument before any `--`, in a segment whose
#     command word (after any NAME=value prefixes) is not echo or printf.
#
# NOT MATCHED: the same text in quotes, a comment or a heredoc body; `until` as
# an argument (`git log --grep until`); `--watch=<value>`, `--watch-path` and
# other words that only start with `--watch`; short flags (`-w`) and the
# `watch` command; a wait inside a `bash -c` operand, a double-quoted `"$(...)"`
# or a heredoc a shell reads; the PowerShell tool. Foreground `sleep` is the
# Bash tool's own block. Known false positives: `until` after `)`, `}` or one
# of the words above used as an argument (`echo $(date) until noon`).
#
# Posture: fail-open. Missing jq, a payload that is not JSON and a NUL byte all
# allow, because this guard advises on a command shape and the row's
# fail-closed guards already deny those payloads.
#
# Kill switch: block_foreground_wait_enabled userConfig option.
#
# BLOCKING: exits 2 on a match.

set -uo pipefail

# Kill switch FIRST, above every source. scripts/check-killswitch-hoist.sh
# pins this line.
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_FOREGROUND_WAIT_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-foreground-wait PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

hook::buffer_stdin_to INPUT || exit 0

# jq-free pre-filter: a payload with neither word cannot match.
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

# Read only once the text could match: a boolean is not a string the fast path
# proves, so this call costs a jq process.
hook::jq_fields "$INPUT" '.tool_input.run_in_background' || exit 0
[[ "${HOOK_JQ_FIELDS[0]-}" == true ]] && exit 0

FWG_HIT=""
# The parse callback: a `--watch` argument in a segment that runs a program.
# shellcheck disable=SC2329  # invoked by hook::bash_parse_segments
fwg::segment() {
  ((FWG_WATCH)) && [[ -z "$FWG_HIT" ]] || return 0
  local -a words=("$@")
  local i=0 n=$#
  while ((i < n)) && [[ "${words[i]}" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do ((i++)); done
  ((i < n)) || return 0
  case "${words[i]##*/}" in
  echo | printf) return 0 ;;
  *) ;;
  esac
  for ((i++; i < n; i++)); do
    [[ "${HOOK_SEG_WORD_QUOTED[i]-0}" == 0 ]] || continue
    case "${words[i]}" in
    --) return 0 ;;
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

# fwg::bare_text: set FWG_BARE to the command with each heredoc body, quoted
# span, escaped character and comment replaced, so `until` is matched only
# where bash reads it as a keyword. The body offsets are bytes, so this runs
# under C.
# shellcheck disable=SC2329  # invoked through hook::_c_locale
fwg::bare_text() {
  local e s t at=0 text="" rest out="" c
  for e in ${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"}; do
    s="${e%% *}"
    e="${e#* }"
    t="${e%% *}"
    # A body nested in an earlier one is already cut.
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
      # In `$'...'` a backslash escapes the next character, `\'` included.
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
