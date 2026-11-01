#!/usr/bin/env bash
# PreToolUse hook: deny a Bash command that opens with `cd <path>` and then runs
# git or writes to a relative path.
#
# `cd <dir> && git ...` matches no permission allow rule, so each one prompts or
# is refused, while `git -C <abs dir> ...` with absolute paths can match one.
# This guard denies the shape with that rewrite as the reason (a relative write
# with no git gets the absolute-path rewrite instead); it widens no allow.
#
# MATCHED: the command text opens with `cd <word>` (bare, or one single- or
# double-quoted word) followed by `&&`, `;` or a newline, and a later top-level
# segment has git as its command word (after any NAME=value prefixes, by
# basename, `.exe` dropped) or writes (`>`, `>>`, `<>`, `>&`) to a relative
# path. Segments come from hook::bash_parse_segments, so a quoted `>` or `git`
# is not a match.
#
# NOT MATCHED: `cd .`, `cd ./`, and a `cd` to the payload's `cwd`; `cd` with no
# operand or with options; a `cd` that is not the first segment; a redirect
# target that is absolute, starts with `~`, `$` or `\`, is a drive path, or is
# an fd dup (`2>&1`); the PowerShell tool. Known gaps: a `&>` or `>|` write,
# which the parser splits at the `&` or `|`, and git behind a wrapper word
# (`command git`, `sudo git`, `env git`).
#
# Posture: fail-open. Missing jq, a payload that is not JSON and a NUL byte all
# allow, because this guard advises on a command shape and the row's
# fail-closed guards already deny those payloads.
#
# Kill switch: block_cd_prefix_enabled userConfig option.
#
# BLOCKING: exits 2 on a match.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off. scripts/check-killswitch-hoist.sh
# pins this line.
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_CD_PREFIX_ENABLED:-true}" == "true" ]] || exit 0

# Parameter expansion, not `dirname`: a command substitution forks, and on
# Windows Git Bash a fork is a process.
_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-cd-prefix PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

hook::buffer_stdin_to INPUT || exit 0

# jq-free pre-filter: a payload with no `cd` then a space or a JSON-escaped tab
# cannot match.
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

# cdp::norm_to <var> <path>: `\` as `/`, trailing slashes dropped, and on
# Windows lowercased with `/c/...` read as `c:/...`, so a `cd` operand compares
# with the payload `cwd`.
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

# cdp::relative_target <op> <target>: true when the redirect writes a relative path.
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
# The parse callback: segment 1 must be exactly `cd <path>`; each later one is
# checked for a git command word and a relative write.
# shellcheck disable=SC2329  # invoked by hook::bash_parse_segments
cdp::segment() {
  CDP_SEG=$((CDP_SEG + 1))
  if ((CDP_SEG == 1)); then
    (($# == 2)) && [[ "$1" == cd ]] && CDP_DIR="$2"
    return 0
  fi
  [[ -n "$CDP_DIR" && -z "$CDP_HIT" ]] || return 0
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
    # A git segment keeps its git hit: the git reason covers its write too.
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

# The reason follows the hit: a relative write with no git in its segment gets
# no git rewrite, which would not apply to it.
# shellcheck disable=SC2016  # the backticks are literal text in the reasons
if [[ "$CDP_HIT" == git ]]; then
  echo 'BLOCKED: Run `git -C <abs path> ...` with absolute paths instead of `cd`; for a multi-line commit message, Write the message to a file and use `git commit -F <file>`.' >&2
else
  echo 'BLOCKED: Write to an absolute path, and run the command with its own directory option (for example `make -C <abs path>`) or an absolute path instead of `cd`.' >&2
fi
exit 2
