#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-no-verify PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require_jq_blocking "guardrails-block-no-verify" "block_no_verify_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' || jq_rc=$?
guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"

MAX_COMMAND_LEN=16384

SUBJECT="" # predeclared: the _to helper assigns through a nameref (SC2154)
hook::extract_bash_subject_to SUBJECT "$TOOL_NAME" "$COMMAND"

HM_ALT=""
IFS=',' read -ra _hm_list <<<"${CLAUDE_PLUGIN_OPTION_BLOCK_NO_VERIFY_HOOK_MANAGER_PREFIXES:-lefthook,husky,pre_commit,simple_git_hooks}"
for _hm in "${_hm_list[@]}"; do
  _hm="${_hm//[^a-zA-Z0-9_]/}"
  _hm="${_hm,,}"
  [[ -n "$_hm" ]] && HM_ALT="${HM_ALT:+$HM_ALT|}$_hm"
done
[[ -n "$HM_ALT" ]] || HM_ALT="lefthook"

PS_HM_ENV_DISABLED=0

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$SUBJECT" form "$2"
  hook::emit_telemetry "block-no-verify" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block() {
  local form="$1"
  shift
  (($#)) && printf '%s\n' "$@" >&2
  emit_tel "blocked" "$form"
  exit 2
}

BYPASS_FIX="Fix what the hook reports instead."

ALIAS_NAMES=()
ALIAS_VALUES=()
ALIAS_DEPTH=0

alias_record() {
  local key
  local -a pos=()
  while (($# > 0)); do
    case "$1" in
    --get | --get-all | --get-regexp | --get-urlmatch | --get-color | --get-colorbool | \
      --unset | --unset-all | --remove-section | --rename-section | -l | --list | -e | --edit) return 0 ;;
    -f | --file | --blob | -t | --type | --default | --comment) shift ;;
    -*) ;;
    *) pos+=("$1") ;;
    esac
    shift
  done
  case "${pos[0]:-}" in
  get | unset | list | edit | remove-section | rename-section) return 0 ;;
  set) pos=("${pos[@]:1}") ;;
  *) ;;
  esac
  ((${#pos[@]} >= 2)) || return 0
  key="${pos[0],,}"
  [[ "$key" == alias.?* ]] || return 0
  ALIAS_NAMES+=("${key#alias.}")
  ALIAS_VALUES+=("${pos[1]}")
}

hookspath_write_check() {
  local -a pos=()
  local scoped=0 top f
  while (($# > 0)); do
    case "$1" in
    --get | --get-all | --get-regexp | --get-urlmatch | --unset | --unset-all | \
      --remove-section | --rename-section | -l | --list | -e | --edit) return 0 ;;
    -f | --file | --blob)
      scoped=1
      shift
      ;;
    -t | --type | --default | --comment) shift ;;
    --local | --add | --replace-all | --fixed-value | --no-includes | --includes | --show-origin) ;;
    -*) scoped=1 ;;
    *) pos+=("$1") ;;
    esac
    shift
  done
  case "${pos[0]:-}" in
  get | unset | list | edit | remove-section | rename-section) return 0 ;;
  set) pos=("${pos[@]:1}") ;;
  *) ;;
  esac
  ((${#pos[@]} >= 2)) || return 0
  [[ "${pos[0],,}" == core.hookspath ]] || return 0
  ((HOOK_GITINV_SUB_IDX == HOOK_GITINV_GI + 1)) || scoped=1
  if [[ "${pos[1]}" == .githooks ]] && ((scoped == 0)); then
    top="$(hook::git_untrusted rev-parse --show-toplevel 2>/dev/null)" || top=""
    if [[ -n "$top" && -d "$top/.githooks" && ! -L "$top/.githooks" ]]; then
      for f in "$top"/.githooks/{pre-commit,pre-push,commit-msg}; do
        [[ -f "$f" && ! -L "$f" ]] && grep -qs '^# checks-dispatcher v1$' "$f" && return 0
      done
    fi
  fi
  block "hooksPath-config" \
    "BLOCKED: git config core.hooksPath ${pos[1]} points every later commit and push at other hooks. Only .githooks, set at local scope while it holds the guardrails dispatcher, is allowed. $BYPASS_FIX"
}

alias_expand() {
  local name="${1,,}" idx=$2 i v
  local -a ALIAS_HEAD ALIAS_TAIL defs=()
  if [[ "$HOOK_GITINV_ALIAS_TERM" == "config-env" ]]; then
    guard::refuse_config_env_alias "$1"
    block "config-env-alias"
  fi
  [[ "$HOOK_GITINV_ALIAS_TERM" == "inline" ]] && defs=("${HOOK_GITINV_ALIAS_EXPS[@]}")
  shift 2
  ALIAS_HEAD=("${@:1:idx}")
  ALIAS_TAIL=("${@:idx+2}")
  ((ALIAS_DEPTH < 5)) || return 0 # git itself refuses an alias loop
  for ((i = ${#ALIAS_NAMES[@]} - 1; i >= 0; i--)); do
    [[ "${ALIAS_NAMES[i]}" == "$name" ]] || continue
    defs+=("${ALIAS_VALUES[i]}")
    break
  done
  for v in ${defs[@]+"${defs[@]}"}; do
    ((ALIAS_DEPTH++))
    if [[ "$v" == '!'* ]]; then
      hook::bash_parse_segments "${v:1}" alias_recheck_shell
    else
      hook::bash_parse_segments "git $v" alias_recheck
    fi
    ((ALIAS_DEPTH--))
  done
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
alias_recheck() {
  check_segment "${ALIAS_HEAD[@]}" "${@:2}" ${ALIAS_TAIL[@]+"${ALIAS_TAIL[@]}"}
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
alias_recheck_shell() {
  check_segment "$@" ${ALIAS_TAIL[@]+"${ALIAS_TAIL[@]}"}
}

# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=("$@")
  local nseg gi k x lc ch rest sub sub_idx cv

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  hook::git_invocation "${w[@]}" || return 0
  gi=$HOOK_GITINV_GI
  w=("${HOOK_GITINV_WORDS[@]}")
  nseg=${#w[@]}
  sub=$HOOK_GITINV_SUB
  sub_idx=$HOOK_GITINV_SUB_IDX
  case "$sub" in
  commit | push) ;;
  config)
    hookspath_write_check "${w[@]:sub_idx+1}"
    alias_record "${w[@]:sub_idx+1}"
    return 0
    ;;
  *)
    alias_expand "$sub" "$sub_idx" "${w[@]}"
    return 0
    ;;
  esac

  for cv in ${HOOK_GITINV_CONFIG_VALUES[@]+"${HOOK_GITINV_CONFIG_VALUES[@]}"}; do
    lc="${cv,,}"
    [[ "$lc" == *core.hookspath=* ]] && block "hooksPath" \
      "BLOCKED: a core.hooksPath override disables every git hook. $BYPASS_FIX"
  done

  for ((k = 0; k < gi; k++)); do
    lc="${w[k],,}"
    [[ "$lc" =~ ^(${HM_ALT})[_a-z0-9]*=(0|false)$ ]] && block "hook-manager-env" \
      "BLOCKED: ${w[k]} disables the hook manager for this git $sub. $BYPASS_FIX"
  done

  ((PS_HM_ENV_DISABLED)) && block "hook-manager-env" \
    "BLOCKED: a hook-manager env var set to 0 or false (HUSKY, LEFTHOOK, ...) disables the hooks for this git $sub. $BYPASS_FIX"

  local nv_msg="BLOCKED: --no-verify / -n skips the hooks on this git $sub. $BYPASS_FIX"
  k=$((sub_idx + 1))
  while ((k < nseg)); do
    x="${w[k]}"
    case "$x" in
    -m | --message | -F | --file | -t | --template | -c | -C | --author | --date)
      ((k += 2))
      continue
      ;;
    --message=* | --file=* | --template=* | --author=* | --date=*)
      ((k++))
      continue
      ;;
    *) ;;
    esac
    [[ "$x" == "--no-verify" ]] && block "no-verify" "$nv_msg"
    if [[ "$sub" == "commit" && "$x" =~ ^-[A-Za-z]+$ ]]; then
      rest="${x#-}"
      for ((ch = 0; ch < ${#rest}; ch++)); do
        case "${rest:ch:1}" in
        n) block "no-verify" "$nv_msg" ;;
        m | F | c | C | t | u | S | G)
          if ((ch + 1 < ${#rest})); then
            ((k++))
          elif ((k + 1 < nseg)); then
            ((k += 2))
          else
            ((k++))
          fi
          continue 2
          ;;
        *) ;;
        esac
      done
    fi
    ((k++))
  done

  return 0
}

if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  block "too-long" \
    "BLOCKED: command over $MAX_COMMAND_LEN chars is too long to check. Split it into shorter commands."
fi

sink_allowed() {
  local tok="$1" list=",${CLAUDE_PLUGIN_OPTION_BLOCK_DANGEROUS_GIT_ALLOW:-},"
  case "$tok" in
  ps-unparsable-dynamic-invocation | ps-unparsable-launcher | \
  ps-unparsable-special-construct | ps-unparsable-herestring-unbalanced | \
  ps-unparsable-herestring-subexpr) ;;
  *) return 1 ;;
  esac
  [[ "$list" == *,"$tok",* ]]
}

ps_env_disables_hook_manager() {
  local lc="${1,,}" scan head tail q=$'[\'"]?'
  [[ "$lc" == *env:* ]] || return 1
  ps::blank_herestrings "$1"
  ps::blank_quoted_spans_to scan "$PS_BLANKED"
  scan="${scan,,}"
  head="\\\$(\\{env:|env:)(${HM_ALT})[_a-z0-9]*\\}?[[:space:]]*="
  tail="[[:space:]]*${q}(0|false)${q}([^[:alnum:]_]|\$)"
  [[ "$scan" =~ $head ]] && [[ "$lc" =~ ${head}${tail} ]] && return 0
  [[ "$scan" =~ (^|[^[:alnum:]_-])(set-item|si)[[:space:]] ]] && ps_set_item_disables "$lc"
}

ps_set_item_disables() {
  local rest="$1" tok name want path val
  local -a toks
  local re=$'(^|[^[:alnum:]_-])(set-item|si)[[:space:]]+([^;|&)}\r\n]*)'
  while [[ "$rest" =~ $re ]]; do
    read -ra toks <<<"${BASH_REMATCH[3]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    path="" val="" want=""
    for tok in ${toks[@]+"${toks[@]}"}; do
      tok="${tok//[\'\"]/}"
      if [[ -n "$want" ]]; then
        [[ "$want" == path ]] && path="$tok" || val="$tok"
        want=""
      elif [[ "$tok" =~ ^-([a-z]+)(:(.*))?$ ]]; then
        name="${BASH_REMATCH[1]}"
        want=""
        if [[ value == "$name"* ]]; then
          want=value
        elif [[ literalpath == "$name"* ]] || { [[ path == "$name"* ]] && ((${#name} > 1)); }; then
          want=path
        fi
        if [[ -n "$want" && -n "${BASH_REMATCH[2]}" ]]; then
          [[ "$want" == path ]] && path="${BASH_REMATCH[3]}" || val="${BASH_REMATCH[3]}"
          want=""
        fi
      elif [[ -z "$path" ]]; then
        path="$tok"
      else
        val="$tok"
      fi
    done
    [[ "$path" =~ ^env:[\\/]?(${HM_ALT})[_a-z0-9]*$ && "$val" =~ ^(0|false)$ ]] && return 0
  done
  return 1
}

if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  # shellcheck source=guard-requires.sh
  declare -F guard::require_libs >/dev/null || source "$_HOOK_SELF/guard-requires.sh"
  guard::require_libs
  ps_env_disables_hook_manager "$COMMAND" && PS_HM_ENV_DISABLED=1
  ps::classify_git_command "$TOOL_NAME" "$COMMAND" "readonly-ok"
  _ps_rc=$?
  _ps_sink_attempts=0
  while ((_ps_rc == 2)); do
    if ((PS_REDUCTION_UNTRUSTED)); then
      PS_SINK_TRIGGER="${PS_REDUCTION_UNTRUSTED_REASON:-herestring-comment-char}"
      ps::print_unparsable_block_message "$COMMAND"
      emit_tel "blocked" "powershell-unparsable-${PS_SINK_TRIGGER}"
      exit 2
    fi
    if ((_ps_sink_attempts > 4)); then
      ps::print_sink_budget_message
      emit_tel "blocked" "powershell-unparsable-budget-exhausted"
      exit 2
    fi
    sink_allow="ps-unparsable-${PS_SINK_TRIGGER:-unknown}"
    if ! sink_allowed "$sink_allow"; then
      ps::print_unparsable_block_message "$COMMAND"
      emit_tel "blocked" "powershell-unparsable-${PS_SINK_TRIGGER:-unknown}"
      exit 2
    fi
    ps::blank_sink_opaque_regions "$COMMAND" "${PS_SINK_TRIGGER:-unknown}"
    COMMAND="$PS_SAFE_COMMAND"
    if [[ -z "${COMMAND//[[:space:]]/}" ]]; then
      emit_tel "ok" ""
      exit 0
    fi
    _ps_sink_attempts=$((_ps_sink_attempts + 1))
    ps::classify_git_command "$TOOL_NAME" "$COMMAND" "readonly-ok"
    _ps_rc=$?
  done
  case $_ps_rc in
  1) exit 0 ;; # non-commit PowerShell with an A2b-deferred construct — not this guard's proven surface
  *) COMMAND="$PS_SAFE_COMMAND" ;;
  esac
fi

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok" ""
exit 0
