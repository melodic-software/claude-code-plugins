#!/usr/bin/env bash

set -uo pipefail

_RG_DIR="${BASH_SOURCE[0]%/*}"
[[ "$_RG_DIR" == "${BASH_SOURCE[0]}" ]] && _RG_DIR=.
# shellcheck source=abort-boundary.sh
source "$_RG_DIR/abort-boundary.sh"
if [[ "${1-}" == --batch ]]; then
  [[ -d "${2-}" ]] || exit 70
  _RG_BATCH=$2
  shift 2
  # shellcheck source=hook-utils.sh
  source "$_RG_DIR/hook-utils.sh" || exit 70
  for ((_RG_I = 1; ; _RG_I++)); do
    [[ -f "$_RG_BATCH/$_RG_I.in" ]] || break
    # shellcheck source=/dev/null  # this script itself; following it would recurse
    (source "$_RG_DIR/${BASH_SOURCE[0]##*/}" "$@") <"$_RG_BATCH/$_RG_I.in" >"$_RG_BATCH/$_RG_I.out"
    printf '%s\n' "$?" >"$_RG_BATCH/$_RG_I.rc"
  done
  exit 0
fi
# Abort posture: open with a notice, closed under --require-verdict, labeled PreToolUse:
# https://code.claude.com/docs/en/hooks#preskillshellcommand-decision-control
guard::abort_boundary run-guards PreToolUse open 0 2
[[ -z "${EXEC_BASH_VERDICT_FILE-}" ]] || guard::abort_boundary run-guards PreToolUse closed 0 2
# shellcheck source=hook-utils.sh
source "$_RG_DIR/hook-utils.sh" || exit 70
HOOK_BPS_MEMO=1

case "$_RG_DIR" in
/* | ?:[/\\]*) HOOK_DIR="$_RG_DIR" ;;
*) HOOK_DIR="$(cd "$_RG_DIR" && pwd)" ;;
esac

RUN_GUARDS_START=${EPOCHREALTIME:-}
GUARDS=()
LIBS=()
RUN_GUARDS_OPTS=()
RUN_GUARDS_MAX_SUBST=0
RUN_GUARDS_MAX_CMD=0
RUN_GUARDS_REPORT=0
RUN_GUARDS_SEEDED=0
while (($#)); do
  case "$1" in
  --max-substitutions)
    [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || exit 70
    RUN_GUARDS_MAX_SUBST=$2
    RUN_GUARDS_OPTS+=("$1" "$2")
    shift 2
    ;;
  --max-command-len)
    [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || exit 70
    RUN_GUARDS_MAX_CMD=$2
    RUN_GUARDS_OPTS+=("$1" "$2")
    shift 2
    ;;
  --report)
    RUN_GUARDS_REPORT=1
    _GUARD_SAID="${2-}"
    shift 2
    ;;
  --bps-seeded)
    RUN_GUARDS_SEEDED=1
    RUN_GUARDS_OPTS+=("$1")
    shift
    ;;
  --lib)
    LIBS+=("$2")
    RUN_GUARDS_OPTS+=("$1" "$2")
    shift 2
    ;;
  *)
    GUARDS+=("$1")
    shift
    ;;
  esac
done
if ((RUN_GUARDS_SEEDED)) && [[ -n "${HOOK_BPS_SEED_KEY+x}" && -n "${HOOK_BPS_SEED_VAL+x}" ]]; then
  HOOK_BPS_MEMO_KEY+=("$HOOK_BPS_SEED_KEY")
  HOOK_BPS_MEMO_VAL+=("$HOOK_BPS_SEED_VAL")
fi
unset HOOK_BPS_SEED_KEY HOOK_BPS_SEED_VAL

run_guards::verdict() {
  ((RUN_GUARDS_REPORT)) || [[ -z "${EXEC_BASH_VERDICT_FILE-}" ]] || : >"$EXEC_BASH_VERDICT_FILE"
}

((${#GUARDS[@]})) || {
  run_guards::verdict
  exit 0
}

RUN_GUARDS_PRIMED=0
declare -A RUN_GUARDS_FIELD=()
PRIME_FILTERS=(
  '.tool_input.command' '.tool_name' '.cwd'
  '.tool_input.file_path' '.tool_input.notebook_path' '.tool_input.path'
  '.tool_input.content' '.tool_input.new_string' '.tool_input.new_source'
)

RUN_GUARDS_INPUT=""
RUN_GUARDS_STDIN_RC=0
hook::buffer_stdin_to RUN_GUARDS_INPUT "${PRIME_FILTERS[@]}" || RUN_GUARDS_STDIN_RC=$?
if ((RUN_GUARDS_STDIN_RC == 1)); then
  run_guards::verdict
  exit 0
fi
if ((RUN_GUARDS_STDIN_RC == 3)); then
  hook::stdin_cut_short_notice "" "guardrails"
  run_guards::verdict
  exit 0
fi

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::buffer_stdin() {
  ((RUN_GUARDS_STDIN_RC == 0)) || return "$RUN_GUARDS_STDIN_RC"
  printf '%s' "$RUN_GUARDS_INPUT"
}

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::buffer_stdin_to() {
  local __rg_dest="$1"
  ((RUN_GUARDS_STDIN_RC == 0)) || return "$RUN_GUARDS_STDIN_RC"
  printf -v "$__rg_dest" '%s' "$RUN_GUARDS_INPUT"
}

if ((RUN_GUARDS_STDIN_RC == 0)) &&
  ((${#HOOK_JQ_FIELDS[@]} == ${#PRIME_FILTERS[@]})) &&
  ((HOOK_JQ_FIELDS_NUL == 0)); then
  RUN_GUARDS_PRIMED=1
  for _rg_i in "${!PRIME_FILTERS[@]}"; do
    RUN_GUARDS_FIELD["${PRIME_FILTERS[_rg_i]}"]="${HOOK_JQ_FIELDS[_rg_i]}"
  done
  unset _rg_i
fi

run_guards::count_subst() {
  local t="$1" rest pat
  _rg_subst=0
  # shellcheck disable=SC2016  # literal spellings, matched as text
  for pat in '$(' '<(' '>('; do
    rest=${t//"$pat"/}
    _rg_subst=$((_rg_subst + (${#t} - ${#rest}) / 2))
  done
  rest=${t//'`'/}
  _rg_subst=$((_rg_subst + (${#t} - ${#rest} + 1) / 2))
}

# shellcheck disable=SC2016,SC1003  # regexes and literal spellings, not expansions
run_guards::counted_text() {
  local LC_ALL=C rest="$1" out="" m d t re_end ws=1 dq=0 br=0 hd=0 n=0
  local nl=$'\n' tab=$'\t'
  local re_plain='^[^'\''"\`$<#]*' re_dq='^[^"\$`]*' re_sq="^'([^']*)'"
  local re_cmt="^#[^$nl]*" re_base='[/\]([^/\]*)$' re_name='^[a-zA-Z0-9_.+-]*$'
  local w='[a-zA-Z0-9_]'
  local re_hd="^<<(-?)[ $tab]*(($w|'$w*'|\"$w*\"|\\\\$w)+)([ $tab;&|>][^'\"\`\\\$#<()$nl]*)?$nl"
  local re_reparse='(^|[^a-z0-9_.-])(eval|source|bash|sh|zsh|dash|ksh|mksh|wsl|su|runuser|sg|env|flock)([^a-z0-9_-]|$)'
  local re_dot="(^|[^a-z0-9_.-])\\.([ $tab{\`\$]|\$)"
  _rg_counted=$1
  m=${1,,}
  [[ $m == *alias* ]] && return 0
  while [[ -n $rest ]] && ((++n <= 1024)); do
    if ((dq)); then
      [[ $rest =~ $re_dq ]]
      out+=${BASH_REMATCH[0]}
      rest=${rest:${#BASH_REMATCH[0]}}
      case $rest in
      '"'*)
        out+='"'
        rest=${rest:1}
        dq=0
        ;;
      '\'?*)
        out+=${rest:0:2}
        rest=${rest:2}
        ;;
      '$('* | '${'* | '$['*) break ;;
      '$'?*)
        out+='$'
        rest=${rest:1}
        ;;
      *) break ;;
      esac
      continue
    fi
    [[ $rest =~ $re_plain ]]
    m=${BASH_REMATCH[0]}
    if [[ -n $m ]]; then
      out+=$m
      rest=${rest:${#m}}
      [[ $m == *[\[\{]* || $m == *'(('* ]] && br=1
      [[ -n $rest ]] || break
      case ${m: -1} in
      [$' \t\n;&|()>']) ws=1 ;;
      *) ws=0 ;;
      esac
    fi
    case $rest in
    "'"*)
      ((br == 0 && hd == 0)) && [[ $out != *'$' && $rest =~ $re_sq ]] || break
      m=${BASH_REMATCH[1]}
      rest=${rest:$((${#m} + 2))}
      [[ $m =~ $re_base ]] && m=${BASH_REMATCH[1]}
      if [[ $m =~ $re_name ]]; then out+=$m; else out+=' '; fi
      ws=0
      ;;
    '"'*)
      out+='"'
      rest=${rest:1}
      dq=1
      ws=0
      ;;
    '\'?*)
      [[ ${rest:1:1} == "$nl" ]] || ws=0
      out+=${rest:0:2}
      rest=${rest:2}
      ;;
    '\')
      out+=$rest
      rest=""
      ;;
    "\$'"* | "\$\$'"*) break ;;
    '$$'*)
      out+='$$'
      rest=${rest:2}
      ws=0
      ;;
    '$'*)
      out+='$'
      rest=${rest:1}
      ws=0
      ;;
    '<<<'*)
      out+='<<<'
      rest=${rest:3}
      ws=1
      ;;
    '<<'*)
      ((br == 0)) && [[ $out != *['$<>']'('* && $rest =~ $re_hd ]] || break
      m=${BASH_REMATCH[0]}
      d=${BASH_REMATCH[2]//[\'\"\\]/}
      [[ -n $d && $d != "${BASH_REMATCH[2]}" ]] || break
      re_end=$nl
      [[ -n ${BASH_REMATCH[1]} ]] && re_end+="$tab*"
      re_end+=$d$nl
      t=$nl${rest:${#m}}$nl
      [[ $t =~ $re_end ]] || break
      out+=$m
      m=${t%%"${BASH_REMATCH[0]}"*}
      rest=${t:$((${#m} + ${#BASH_REMATCH[0]}))}
      rest=${rest%"$nl"}
      ws=1
      hd=1
      ;;
    '<'*)
      out+='<'
      rest=${rest:1}
      ws=1
      ;;
    '#'*)
      if ((ws)); then
        [[ $rest =~ $re_cmt && ${BASH_REMATCH[0]} != *[\'\"\`]* ]] || break
        out+=${BASH_REMATCH[0]}
        rest=${rest:${#BASH_REMATCH[0]}}
      else
        out+='#'
        rest=${rest:1}
      fi
      ;;
    *) break ;;
    esac
  done
  m=$out$rest
  m=${m//\"/}
  m=${m,,}
  [[ $m =~ $re_reparse || ${m//\\/} =~ $re_reparse || $m =~ $re_dot ]] || _rg_counted=$out$rest
}

RUN_GUARDS_OVERLONG=0
if ((RUN_GUARDS_STDIN_RC == 0 && (RUN_GUARDS_MAX_SUBST || RUN_GUARDS_MAX_CMD))); then
  if ((RUN_GUARDS_PRIMED)); then
    _rg_text="${RUN_GUARDS_FIELD['.tool_input.command']-}"
  else
    _rg_text=$RUN_GUARDS_INPUT
  fi
  ((RUN_GUARDS_MAX_CMD && ${#_rg_text} > RUN_GUARDS_MAX_CMD)) && RUN_GUARDS_OVERLONG=1
fi

if ((RUN_GUARDS_MAX_SUBST && RUN_GUARDS_STDIN_RC == 0)); then
  _rg_data=""
  run_guards::count_subst "$_rg_text"
  if ((_rg_subst > RUN_GUARDS_MAX_SUBST && RUN_GUARDS_PRIMED && !RUN_GUARDS_OVERLONG)) &&
    [[ "${RUN_GUARDS_FIELD['.tool_name']-}" == Bash && ($_rg_text == *"'"* || $_rg_text == *'<<'*) ]]; then
    run_guards::counted_text "$_rg_text"
    run_guards::count_subst "$_rg_counted"
    unset _rg_counted
  fi
  unset -f run_guards::count_subst run_guards::counted_text
  if ((_rg_subst > RUN_GUARDS_MAX_SUBST)); then
    echo "BLOCKED: $_rg_subst command or process substitutions, over the $RUN_GUARDS_MAX_SUBST the guards can check in time. Split the command, or run the work from a script file." >&2
    if hook::telemetry_enabled; then
      hook::json_str_object_to _rg_data tool "${RUN_GUARDS_FIELD['.tool_name']-}" form "too-many-substitutions" count "$_rg_subst"
      hook::emit_telemetry run-guards PreToolUse blocked "$RUN_GUARDS_START" "$_rg_data" "${CLAUDE_PROJECT_DIR:-}"
    fi
    run_guards::verdict
    exit 2
  fi
  unset _rg_subst _rg_data
fi
unset _rg_text

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::jq_fields() {
  local input="$1"
  shift
  (($#)) || return 1
  if ((RUN_GUARDS_PRIMED)) && [[ "$input" == "$RUN_GUARDS_INPUT" ]]; then
    local -a out=()
    local filter
    for filter in "$@"; do
      [[ -n "${RUN_GUARDS_FIELD[$filter]+x}" ]] || break
      out+=("${RUN_GUARDS_FIELD[$filter]}")
    done
    if ((${#out[@]} == $#)); then
      HOOK_JQ_FIELDS=("${out[@]}")
      HOOK_JQ_FIELDS_NUL=0
      return 0
    fi
  fi
  hook::jq_fields_uncached "$input" "$@" || return
  if ((RUN_GUARDS_PRIMED && HOOK_JQ_FIELDS_NUL == 0)) && [[ "$input" == "$RUN_GUARDS_INPUT" ]]; then
    local __rg_i=0 __rg_f
    for __rg_f in "$@"; do
      RUN_GUARDS_FIELD["$__rg_f"]="${HOOK_JQ_FIELDS[__rg_i]}"
      __rg_i=$((__rg_i + 1))
    done
  fi
  return 0
}

RUN_GUARDS_RFP_KEY=""
RUN_GUARDS_RFP_RC=""
RUN_GUARDS_RFP_VAL=""
# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::read_file_path_to() {
  local __rg_key="${CLAUDE_PROJECT_DIR-}|${HOOK_READ_FILE_PATH_UNSCOPED:-0}" __rg_val="" __rg_rc=0
  if (($# != 2)) || [[ "$2" != "$RUN_GUARDS_INPUT" ]]; then
    hook::read_file_path_uncached_to "$@"
    return
  fi
  if [[ -z "$RUN_GUARDS_RFP_RC" || "$__rg_key" != "$RUN_GUARDS_RFP_KEY" ]]; then
    hook::read_file_path_uncached_to __rg_val "$2" || __rg_rc=$?
    RUN_GUARDS_RFP_KEY=$__rg_key
    RUN_GUARDS_RFP_RC=$__rg_rc
    RUN_GUARDS_RFP_VAL=$__rg_val
  fi
  ((RUN_GUARDS_RFP_RC == 0)) || return "$RUN_GUARDS_RFP_RC"
  printf -v "$1" '%s' "$RUN_GUARDS_RFP_VAL"
}

RUN_GUARDS_RR_KEY=""
RUN_GUARDS_RR_RC=""
RUN_GUARDS_RR_VAL=""
RUN_GUARDS_RR_UNRESOLVED=""
# shellcheck disable=SC2329,SC2034  # invoked by the guards; HOOK_REPO_ROOT_UNRESOLVED is their contract
hook::repo_root_to() {
  local __rg_hint="${2:-.}" __rg_key="$PWD|${2:-.}" __rg_val="" __rg_rc=0
  if [[ -z "$RUN_GUARDS_RR_RC" || "$__rg_key" != "$RUN_GUARDS_RR_KEY" ]]; then
    hook::repo_root_uncached_to __rg_val "$__rg_hint" || __rg_rc=$?
    RUN_GUARDS_RR_KEY=$__rg_key
    RUN_GUARDS_RR_RC=$__rg_rc
    RUN_GUARDS_RR_VAL=$__rg_val
    RUN_GUARDS_RR_UNRESOLVED=$HOOK_REPO_ROOT_UNRESOLVED
  fi
  HOOK_REPO_ROOT_UNRESOLVED=$RUN_GUARDS_RR_UNRESOLVED
  printf -v "$1" '%s' "$RUN_GUARDS_RR_VAL"
  return "$RUN_GUARDS_RR_RC"
}

RUN_GUARDS_BPS_HAVE=0
RUN_GUARDS_BPS_KEY=""
RUN_GUARDS_BPS_DEPTH=0
RUN_GUARDS_BPS_ARGC=()
RUN_GUARDS_BPS_REDC=()
RUN_GUARDS_BPS_WORDS=()
RUN_GUARDS_BPS_WQ=()
RUN_GUARDS_BPS_ROP=()
RUN_GUARDS_BPS_RFD=()
RUN_GUARDS_BPS_RTGT=()
RUN_GUARDS_BPS_RQ=()
RUN_GUARDS_BPS_ROPQ=()
RUN_GUARDS_BPS_HD=()

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::bash_parse_segments() {
  if ((RUN_GUARDS_BPS_HAVE)) && [[ "$1" == "$RUN_GUARDS_BPS_KEY" ]]; then
    run_guards::bps_replay "$2"
    return 0
  fi
  if ((RUN_GUARDS_BPS_DEPTH)); then
    hook::bash_parse_segments_uncached "$@"
    return
  fi
  local __rg_bps_cb="$2"
  local -a __rg_bps_argc=() __rg_bps_redc=() __rg_bps_words=() __rg_bps_wq=()
  local -a __rg_bps_rop=() __rg_bps_rfd=() __rg_bps_rtgt=() __rg_bps_rq=() __rg_bps_ropq=()
  RUN_GUARDS_BPS_DEPTH=1
  hook::bash_parse_segments_uncached "$1" run_guards::bps_record
  RUN_GUARDS_BPS_DEPTH=0
  RUN_GUARDS_BPS_KEY=$1
  RUN_GUARDS_BPS_ARGC=(${__rg_bps_argc[@]+"${__rg_bps_argc[@]}"})
  RUN_GUARDS_BPS_REDC=(${__rg_bps_redc[@]+"${__rg_bps_redc[@]}"})
  RUN_GUARDS_BPS_WORDS=(${__rg_bps_words[@]+"${__rg_bps_words[@]}"})
  RUN_GUARDS_BPS_WQ=(${__rg_bps_wq[@]+"${__rg_bps_wq[@]}"})
  RUN_GUARDS_BPS_ROP=(${__rg_bps_rop[@]+"${__rg_bps_rop[@]}"})
  RUN_GUARDS_BPS_RFD=(${__rg_bps_rfd[@]+"${__rg_bps_rfd[@]}"})
  RUN_GUARDS_BPS_RTGT=(${__rg_bps_rtgt[@]+"${__rg_bps_rtgt[@]}"})
  RUN_GUARDS_BPS_RQ=(${__rg_bps_rq[@]+"${__rg_bps_rq[@]}"})
  RUN_GUARDS_BPS_ROPQ=(${__rg_bps_ropq[@]+"${__rg_bps_ropq[@]}"})
  RUN_GUARDS_BPS_HD=(${HOOK_HEREDOC_BODIES[@]+"${HOOK_HEREDOC_BODIES[@]}"})
  RUN_GUARDS_BPS_HAVE=1
}

# shellcheck disable=SC2329  # invoked as the parse callback above
run_guards::bps_record() {
  __rg_bps_argc+=("$#")
  __rg_bps_redc+=("${#HOOK_SEG_REDIR_OP[@]}")
  __rg_bps_words+=("$@")
  __rg_bps_wq+=(${HOOK_SEG_WORD_QUOTED[@]+"${HOOK_SEG_WORD_QUOTED[@]}"})
  __rg_bps_rop+=(${HOOK_SEG_REDIR_OP[@]+"${HOOK_SEG_REDIR_OP[@]}"})
  __rg_bps_rfd+=(${HOOK_SEG_REDIR_FD[@]+"${HOOK_SEG_REDIR_FD[@]}"})
  __rg_bps_rtgt+=(${HOOK_SEG_REDIR_TARGET[@]+"${HOOK_SEG_REDIR_TARGET[@]}"})
  __rg_bps_rq+=(${HOOK_SEG_REDIR_QUOTED[@]+"${HOOK_SEG_REDIR_QUOTED[@]}"})
  __rg_bps_ropq+=(${HOOK_SEG_REDIR_OPAQUE[@]+"${HOOK_SEG_REDIR_OPAQUE[@]}"})
  "$__rg_bps_cb" "$@"
}

run_guards::bps_replay() {
  local __rg_cb="$1" __rg_k __rg_j __rg_a __rg_c __rg_w=0 __rg_r=0
  local __rg_depth=$RUN_GUARDS_BPS_DEPTH
  local -a __rg_argv=()
  RUN_GUARDS_BPS_DEPTH=1
  for ((__rg_k = 0; __rg_k < ${#RUN_GUARDS_BPS_ARGC[@]}; __rg_k++)); do
    __rg_a=${RUN_GUARDS_BPS_ARGC[__rg_k]}
    __rg_c=${RUN_GUARDS_BPS_REDC[__rg_k]}
    __rg_argv=()
    HOOK_SEG_WORD_QUOTED=()
    for ((__rg_j = 0; __rg_j < __rg_a; __rg_j++)); do
      __rg_argv+=("${RUN_GUARDS_BPS_WORDS[__rg_w + __rg_j]}")
      HOOK_SEG_WORD_QUOTED+=("${RUN_GUARDS_BPS_WQ[__rg_w + __rg_j]}")
    done
    HOOK_SEG_REDIR_OP=()
    HOOK_SEG_REDIR_FD=()
    HOOK_SEG_REDIR_TARGET=()
    HOOK_SEG_REDIR_QUOTED=()
    HOOK_SEG_REDIR_OPAQUE=()
    for ((__rg_j = 0; __rg_j < __rg_c; __rg_j++)); do
      HOOK_SEG_REDIR_OP+=("${RUN_GUARDS_BPS_ROP[__rg_r + __rg_j]}")
      HOOK_SEG_REDIR_FD+=("${RUN_GUARDS_BPS_RFD[__rg_r + __rg_j]}")
      HOOK_SEG_REDIR_TARGET+=("${RUN_GUARDS_BPS_RTGT[__rg_r + __rg_j]}")
      HOOK_SEG_REDIR_QUOTED+=("${RUN_GUARDS_BPS_RQ[__rg_r + __rg_j]}")
      HOOK_SEG_REDIR_OPAQUE+=("${RUN_GUARDS_BPS_ROPQ[__rg_r + __rg_j]}")
    done
    __rg_w=$((__rg_w + __rg_a))
    __rg_r=$((__rg_r + __rg_c))
    "$__rg_cb" "${__rg_argv[@]}"
  done
  HOOK_SEG_WORD_QUOTED=()
  HOOK_SEG_REDIR_OP=()
  HOOK_SEG_REDIR_FD=()
  HOOK_SEG_REDIR_TARGET=()
  HOOK_SEG_REDIR_QUOTED=()
  HOOK_SEG_REDIR_OPAQUE=()
  HOOK_HEREDOC_BODIES=(${RUN_GUARDS_BPS_HD[@]+"${RUN_GUARDS_BPS_HD[@]}"})
  RUN_GUARDS_BPS_DEPTH=$__rg_depth
}

_rg_tool="${RUN_GUARDS_FIELD['.tool_name']-}"
if ((${#LIBS[@]})) && [[ "$_rg_tool" != "Bash" ]]; then
  # shellcheck source=guard-requires.sh
  source "$_RG_DIR/guard-requires.sh"
  for _rg_guard in "${GUARDS[@]}"; do
    guard::require_libs "${_rg_guard##*/}"
  done
  unset _rg_guard
  for _rg_lib in "${LIBS[@]}"; do
    guard::require_lib "$_rg_lib"
  done
  unset _rg_lib
fi
unset _rg_tool

RC=0
OUTS=()
RUN_GUARDS_CUR=-1
RUN_GUARDS_PID=$BASHPID
RUN_GUARDS_T0=""

# shellcheck disable=SC2329  # invoked by every guard sourced below
hook::emit_document() {
  OUTS+=("$1")
}

# shellcheck disable=SC2329  # invoked by every fail-closed guard sourced below
hook::require_jq_blocking() {
  command -v jq >/dev/null 2>&1 && return 0
  guard::say_once jq "BLOCKED: jq is not on PATH, so guardrails denies every Bash and PowerShell call, and every file write on Windows. Ask the user to install jq (https://jqlang.org/download/)."
  exit 2
}

# shellcheck disable=SC2329  # invoked by every guard sourced below
exit() {
  local __rg_rc="${1:-$?}"
  [[ "$BASHPID" == "$RUN_GUARDS_PID" ]] || builtin exit "$__rg_rc"
  ((RUN_GUARDS_CUR >= 0)) || builtin exit "$__rg_rc"
  RUN_GUARDS_EXIT_RC=$__rg_rc
  RUN_GUARDS_EXIT_DEPTH=${#FUNCNAME[@]}
  set -T
  shopt -s extdebug
  trap '[[ ${FUNCNAME[0]-} == run_guards::run_from ]] && { trap - DEBUG; shopt -u extdebug; set +T; RUN_GUARDS_UNWOUND=1; } || return 2' DEBUG
  return 0
}

RUN_GUARDS_EXIT_RC=0
RUN_GUARDS_EXIT_DEPTH=0
RUN_GUARDS_UNWOUND=0

# shellcheck disable=SC2329  # invoked through _GAB_CONTINUE by the trap handler
run_guards::guard_died() {
  run_guards::guard_done "$1"
}

run_guards::record() {
  local __rg_rc="$1" __rg_path="${GUARDS[RUN_GUARDS_CUR]}"
  if [[ -n "$_GAB_NAME" ]] && ! guard::_abort_settle "$__rg_rc"; then
    [[ -n "$_GAB_DOC" ]] && OUTS+=("$_GAB_DOC")
    __rg_rc=$_GAB_RC
  fi
  if [[ -n "${RUN_GUARDS_PROFILE:-}" && -n "${EPOCHREALTIME:-}" && -n "$RUN_GUARDS_T0" ]]; then
    local __rg_t1=$EPOCHREALTIME
    printf 'run-guards: %5d ms rc=%d %s\n' "$(((${__rg_t1/./} - ${RUN_GUARDS_T0/./}) / 1000))" "$__rg_rc" "${__rg_path##*/}" >&2
  fi
  run_guards::fold_rc "$__rg_rc"
}

run_guards::fold_rc() {
  local __rg_v="$1"
  if ((__rg_v == 2)); then
    RC=2
  elif ((__rg_v != 0 && RC != 2 && __rg_v > RC)); then
    RC=$__rg_v
  fi
}

RUN_GUARDS_MAX_DEPTH=64

# shellcheck disable=SC2329  # invoked by run_guards::guard_died, itself invoked through _GAB_CONTINUE
run_guards::guard_done() {
  run_guards::record "$1"
  ((RUN_GUARDS_OVERLONG && RC == 2)) && run_guards::finish
  local __rg_next=$((RUN_GUARDS_CUR + 1))
  ((__rg_next < ${#GUARDS[@]})) || run_guards::finish
  run_guards::run_rest "$__rg_next"
  run_guards::finish
}

run_guards::run_from() {
  local __rg_i __rg_rc __rg_path
  for ((__rg_i = $1; __rg_i < ${#GUARDS[@]}; __rg_i++)); do
    RUN_GUARDS_CUR=$__rg_i
    case "${GUARDS[__rg_i]}" in
    */*) __rg_path="${GUARDS[__rg_i]}" ;;
    *) __rg_path="$HOOK_DIR/${GUARDS[__rg_i]}" ;;
    esac
    if [[ ! -f "$__rg_path" ]]; then
      echo "run-guards: guard not found: $__rg_path" >&2
      ((RC < 1)) && RC=1
      continue
    fi
    _GAB_NAME=""
    hook::reset_analysis_state
    RUN_GUARDS_BPS_DEPTH=0
    RUN_GUARDS_T0=${EPOCHREALTIME:-}
    # shellcheck disable=SC1090
    source "$__rg_path" </dev/null
    __rg_rc=$?
    if ((RUN_GUARDS_UNWOUND)); then
      RUN_GUARDS_UNWOUND=0
      __rg_rc=$RUN_GUARDS_EXIT_RC
    fi
    run_guards::record "$__rg_rc"
    ((RUN_GUARDS_OVERLONG && RC == 2)) && break
    if ((RUN_GUARDS_EXIT_DEPTH > RUN_GUARDS_MAX_DEPTH && __rg_i + 1 < ${#GUARDS[@]})); then
      RUN_GUARDS_EXIT_DEPTH=0
      run_guards::run_rest $((__rg_i + 1))
      break
    fi
    RUN_GUARDS_EXIT_DEPTH=0
  done
  run_guards::finish
}

run_guards::run_rest() {
  local __rg_rest="" __rg_doc
  if ((${#FUNCNAME[@]} > RUN_GUARDS_MAX_DEPTH)); then
    if ((RUN_GUARDS_STDIN_RC == 0 && RUN_GUARDS_PRIMED)); then
      __rg_rest=$("$BASH" "$HOOK_DIR/run-guards.sh" --report "$_GUARD_SAID" \
        ${RUN_GUARDS_OPTS[@]+"${RUN_GUARDS_OPTS[@]}"} "${GUARDS[@]:$1}" <<<"$RUN_GUARDS_INPUT")
    fi
  else
    # shellcheck disable=SC2030  # the subshell's own OUTS and RC come back on its stdout
    __rg_rest=$(
      RUN_GUARDS_PID=$BASHPID
      RUN_GUARDS_REPORT=1
      OUTS=()
      RC=0
      run_guards::run_from "$1"
    )
  fi
  while [[ "$__rg_rest" == *$'\x1e'* ]]; do
    __rg_doc=${__rg_rest%%$'\x1e'*}
    __rg_rest=${__rg_rest#*$'\x1e'}
    # shellcheck disable=SC2031  # this is the parent's OUTS, fed from the report
    OUTS+=("$__rg_doc")
  done
  if [[ "$__rg_rest" =~ ^RC=([0-9]+)$ ]]; then
    run_guards::fold_rc "${BASH_REMATCH[1]}"
  else
    echo "BLOCKED: guardrails could not finish checking this call: the guards after ${GUARDS[$1 - 1]##*/} reported no verdict. Split the command into simpler steps." >&2
    RC=2
  fi
}

run_guards::emit_one() {
  local why="$1" pick=-1 i doc
  local re_block='"decision"[[:space:]]*:[[:space:]]*"block"'
  local re_deny='"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'
  local re_ask='"permissionDecision"[[:space:]]*:[[:space:]]*"ask"'
  for i in "${!OUTS[@]}"; do
    doc="${OUTS[i]}"
    if [[ "$doc" =~ $re_block || "$doc" =~ $re_deny ]]; then
      pick=$i
      break
    fi
    ((pick < 0)) && [[ "$doc" =~ $re_ask ]] && pick=$i
  done
  ((pick < 0)) && pick=0
  printf '%s\n' "${OUTS[pick]}"
  ((RC == 2)) && return 0
  for i in "${!OUTS[@]}"; do
    ((i == pick)) && continue
    printf 'run-guards: dropped %s: %s\n' "$why" "${OUTS[i]}" >&2
  done
}

run_guards::finish() {
  RUN_GUARDS_CUR=-1
  _GAB_CONTINUE=""
  # shellcheck disable=SC2031  # each process reads its own: the fork in run_guards::run_rest sets the subshell's
  if ((RUN_GUARDS_REPORT)); then
    local __rg_doc
    for __rg_doc in ${OUTS[@]+"${OUTS[@]}"}; do
      printf '%s\x1e' "$__rg_doc"
    done
    printf 'RC=%d' "$RC"
    builtin exit 0
  fi
  local __rg_posture=open
  ((RC == 2)) && __rg_posture=closed
  [[ -n "${EXEC_BASH_VERDICT_FILE-}" ]] && __rg_posture=closed
  guard::abort_boundary run-guards PreToolUse "$__rg_posture" 0 2
  if ((RC == 2 && ${#OUTS[@]})); then
    local __rg_keep=() __rg_d __rg_re_ask='"permissionDecision"[[:space:]]*:[[:space:]]*"ask"'
    for __rg_d in "${OUTS[@]}"; do
      [[ "$__rg_d" =~ $__rg_re_ask ]] || __rg_keep+=("$__rg_d")
    done
    OUTS=(${__rg_keep[@]+"${__rg_keep[@]}"})
  fi
  if ((${#OUTS[@]} == 1)); then
    printf '%s\n' "${OUTS[0]}"
  elif ((${#OUTS[@]} > 1)); then
    if ! command -v jq >/dev/null 2>&1; then
      run_guards::emit_one "without jq"
    else
      local merged
      merged=$(printf '%s\n' "${OUTS[@]}" | jq -cs '
        (map(.hookSpecificOutput.permissionDecision // empty)) as $d
        | (if any($d[]; . == "deny") then "deny" elif any($d[]; . == "ask") then "ask" else "" end) as $dec
        | { hookSpecificOutput: ({
              hookEventName: (map(.hookSpecificOutput.hookEventName // empty) | .[0] // ""),
              additionalContext: (map(.hookSpecificOutput.additionalContext // empty) | join("\n\n")) }
            + (if $dec == "" then {} else {
                permissionDecision: $dec,
                permissionDecisionReason: (map(select(.hookSpecificOutput.permissionDecision == $dec)
                  | .hookSpecificOutput.permissionDecisionReason // empty) | join("\n\n")) } end)),
            systemMessage: (map(.systemMessage // empty) | join("\n\n")) }
        | if .systemMessage == "" then del(.systemMessage) else . end
        | if .hookSpecificOutput.additionalContext == "" then del(.hookSpecificOutput.additionalContext) else . end
        | if (.hookSpecificOutput | keys) == ["hookEventName"] then del(.hookSpecificOutput) else . end
        | if . == {} then empty else . end' 2>/dev/null)
      merged="${merged//$'\r'/}"
      if [[ -n "$merged" ]]; then
        printf '%s\n' "$merged"
      else
        run_guards::emit_one "(merge failed)"
      fi
    fi
  fi
  guard::abort_boundary_release
  run_guards::verdict
  builtin exit "$RC"
}

_GAB_CONTINUE=run_guards::guard_died
run_guards::run_from 0
