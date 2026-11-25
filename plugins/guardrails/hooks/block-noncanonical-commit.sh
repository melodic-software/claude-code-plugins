#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-noncanonical-commit PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require jq "PreToolUse" guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.cwd' '.tool_name' || exit 0

if ((HOOK_JQ_FIELDS_NUL)); then
  guard::refuse_nul
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
TOOL_NAME="${HOOK_JQ_FIELDS[2]:-Bash}"
RAW_COMMAND="$COMMAND"

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data subject
  hook::extract_bash_subject_to subject "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$subject" form "$2"
  hook::emit_telemetry "block-noncanonical-commit" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Is a form token in the block_noncanonical_commit_allow userConfig comma list?
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
allowed() {
  local tok="$1" list=",${CLAUDE_PLUGIN_OPTION_BLOCK_NONCANONICAL_COMMIT_ALLOW:-},"
  [[ "$list" == *,"$tok",* ]]
}

# msg_count_to <var> <text>: how many times <text> occurs in RAW_COMMAND.
# shellcheck disable=SC2329  # reached via the parse callback chain
msg_count_to() {
  local -n __mc_out="$1"
  local __mc_rest="$RAW_COMMAND" __mc_n=0
  while [[ -n "$2" && "$__mc_rest" == *"$2"* ]]; do
    __mc_n=$((__mc_n + 1))
    __mc_rest="${__mc_rest#*"$2"}"
  done
  __mc_out=$__mc_n
}

# shellcheck disable=SC2329,SC2016  # reached via the parse callback chain; literal `$` patterns
msg_value_interpolates() {
  local v="$1" esc d body re_hd hd rest pre close depth i n_all n_safe n_all_q
  if [[ -n "${PS_HERESTRING_PLACEHOLDER+x}" && "$v" == "$PS_HERESTRING_PLACEHOLDER" ]]; then
    [[ "$RAW_COMMAND" == *'@"'* ]]
    return
  fi
  if [[ "$TOOL_NAME" == "PowerShell" ]]; then
    local re_ps='(^|[[:space:]])-(-m[a-z]*|[a-z]*m)(=|[[:space:]]+)?@?"([^"]|"")*[$`]'
    [[ "$RAW_COMMAND" =~ $re_ps ]]
    return
  fi
  [[ "$v" == *['$`']* ]] || return 1
  msg_count_to n_all "$v"
  if ((n_all > 0)); then
    msg_count_to n_safe "m '$v'"
    msg_count_to n_all_q "m'$v'"
    n_safe=$((n_safe + n_all_q))
    msg_count_to n_all_q "='$v'"
    n_safe=$((n_safe + n_all_q))
    ((n_safe == n_all)) && return 1
  else
    esc="${v//\\/\\\\}"
    esc="${esc//\"/\\\"}"
    esc="${esc//\$/\\\$}"
    esc="${esc//\`/\\\`}"
    msg_count_to n_all "$esc"
    msg_count_to n_safe "m \"$esc\""
    msg_count_to n_all_q "=\"$esc\""
    n_safe=$((n_safe + n_all_q))
    ((n_all > 0 && n_safe == n_all)) && return 1
  fi
  [[ "$v" =~ ^\$(\{[A-Za-z_][A-Za-z0-9_]*\}|[A-Za-z_][A-Za-z0-9_]*)$ ]] && return 1
  re_hd=$'^\\$\\(cat[[:space:]]+<<-?[[:space:]]*[\'"]([A-Za-z_][A-Za-z0-9_]*)[\'"][[:space:]]*\n'
  if [[ "$v" =~ $re_hd ]]; then
    d="${BASH_REMATCH[1]}"
    hd="${BASH_REMATCH[0]}"
    rest="$RAW_COMMAND"
    [[ "$rest" == *"$hd"* ]] || return 0
    while [[ "$rest" == *"$hd"* ]]; do
      pre="${rest%%"$hd"*}"
      close='^[[:space:]]*\)([[:space:];&|)]|$)'
      [[ "$pre" == *\" ]] && close='^[[:space:]]*\)"([[:space:];&|)]|$)'
      body=$'\n'"${rest#*"$hd"}"
      [[ "$body" == *$'\n'"$d"$'\n'* ]] || return 0
      body="${body#*$'\n'"$d"$'\n'}"
      [[ "$body" =~ $close ]] || return 0
      rest="$body"
    done
    return 1
  fi
  [[ "$v" == '$(cat'* ]] && return 0
  [[ "$v" == '$('*')' ]] || return 0
  depth=0
  for ((i = 1; i < ${#v} - 1; i++)); do
    case "${v:i:1}" in
    '(') depth=$((depth + 1)) ;;
    ')')
      depth=$((depth - 1))
      ((depth > 0)) || return 0
      ;;
    *) ;;
    esac
  done
  ((depth != 1))
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
explicit_git_dir_to() {
  local -n _egd_out="$1"
  shift
  local i n=$# arg found=""
  local -a a=("$@")
  for ((i = 0; i < n; i++)); do
    arg="${a[i]}"
    case "$arg" in
    --git-dir)
      ((i + 1 < n)) && found="${a[i + 1]}"
      ((i++))
      ;;
    --git-dir=*) found="${arg#--git-dir=}" ;;
    *) ;;
    esac
  done
  _egd_out="$found"
}

HOOK_EFFECTIVE_LOCATING=()
HOOK_PROBE_LOCATING=()
HOOK_FRAME_PREFIX_HAS_C=0
declare -A _repo_git_probe_cache=()
HOOK_REPO_GIT_PROBE_OUT=""

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
probe_key_to() {
  local -n __pk_out="$1"
  local __pk_q __pk_a
  printf -v __pk_q '%q' "$2"
  __pk_out="$__pk_q"
  shift 2
  for __pk_a in ${HOOK_PROBE_LOCATING[@]+"${HOOK_PROBE_LOCATING[@]}"} "$@"; do
    printf -v __pk_q '%q' "$__pk_a"
    __pk_out+=$'\n'"$__pk_q"
  done
}

# Call as: repo_git_probe <dir> <git-arg>… — sets HOOK_REPO_GIT_PROBE_OUT.
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
repo_git_probe() {
  local dir="$1" key out
  probe_key_to key "$@"
  shift
  if [[ -n "${_repo_git_probe_cache[$key]+x}" ]]; then
    HOOK_REPO_GIT_PROBE_OUT="${_repo_git_probe_cache[$key]}"
    return 0
  fi
  out=$(
    hook::git_untrusted -C "$dir" ${HOOK_PROBE_LOCATING[@]+"${HOOK_PROBE_LOCATING[@]}"} "$@" 2>/dev/null
    printf 'x'
  )
  out="${out%x}"
  out="${out%$'\n'}"
  _repo_git_probe_cache["$key"]="$out"
  HOOK_REPO_GIT_PROBE_OUT="$out"
}

declare -A _alias_launch_dir=()
HOOK_ALIAS_LAUNCH_DIR=""
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
alias_launch_dir() {
  local dir="$1" key toplevel frame_nglob="$2"
  probe_key_to key "$dir"
  if [[ -z "${_alias_launch_dir[$key]+x}" ]]; then
    repo_git_probe "$dir" rev-parse --show-toplevel
    toplevel="$HOOK_REPO_GIT_PROBE_OUT"
    if [[ -z "$toplevel" ]]; then
      _alias_launch_dir["$key"]=""
    else
      repo_git_probe "$dir" rev-parse --show-prefix
      if [[ -n "$HOOK_REPO_GIT_PROBE_OUT" || frame_nglob -eq 0 ]]; then
        _alias_launch_dir["$key"]="$toplevel"
      else
        _alias_launch_dir["$key"]="$dir"
      fi
    fi
  fi
  HOOK_ALIAS_LAUNCH_DIR="${_alias_launch_dir[$key]}"
  [[ -n "$HOOK_ALIAS_LAUNCH_DIR" ]]
}

# Call as: collect_locating_globals <invocation-prefix words...> -> $locating_globals
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
collect_locating_globals() {
  local -a w=("$@")
  local n=$# j=0
  locating_globals=()
  while ((j < n)); do
    case "${w[j]}" in
    --git-dir | --work-tree | --namespace)
      ((j + 1 < n)) && locating_globals+=("${w[j]}" "${w[j + 1]}")
      ((j += 2))
      ;;
    --git-dir=* | --work-tree=* | --namespace=*)
      locating_globals+=("${w[j]}")
      ((j++))
      ;;
    *) ((j++)) ;;
    esac
  done
  return 0
}

# shellcheck disable=SC2329
set_probe_locating() {
  HOOK_PROBE_LOCATING=()
  if ((${#HOOK_EFFECTIVE_LOCATING[@]} && HOOK_FRAME_PREFIX_HAS_C == 0)); then
    HOOK_PROBE_LOCATING=("${HOOK_EFFECTIVE_LOCATING[@]}")
  fi
  HOOK_PROBE_LOCATING+=(${locating_globals[@]+"${locating_globals[@]}"})
}

# shellcheck disable=SC2329
shell_alias_inherited_locating() {
  if ((${#locating_globals[@]})); then
    HOOK_EFFECTIVE_LOCATING=("${HOOK_PROBE_LOCATING[@]}")
  else
    HOOK_EFFECTIVE_LOCATING=()
  fi
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
shell_alias_reparse() {
  local -a saved_locating=(${HOOK_EFFECTIVE_LOCATING[@]+"${HOOK_EFFECTIVE_LOCATING[@]}"})
  HOOK_ALIAS_SEEN=()
  shell_alias_inherited_locating
  HOOK_EFFECTIVE_BASE="$HOOK_ALIAS_LAUNCH_DIR"
  alias_reexpand_admit shell "$1" &&
    hook::bash_parse_segments "$1" check_segment
  HOOK_EFFECTIVE_BASE="$saved_base"
  HOOK_EFFECTIVE_LOCATING=(${saved_locating[@]+"${saved_locating[@]}"})
  HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"} "$sub")
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sequencer_in_progress() {
  local dir f repo="$1" explicit="$2"
  if [[ -n "$explicit" ]]; then
    dir="$explicit"
    [[ "$dir" == /* || "$dir" =~ ^[A-Za-z]:[\/] ]] || dir="$repo/$dir"
  else
    repo_git_probe "$repo" rev-parse --absolute-git-dir
    dir="$HOOK_REPO_GIT_PROBE_OUT"
  fi
  [[ -n "$dir" ]] || return 1
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [[ -e "$dir/$f" ]] && return 0
  done
  return 1
}

declare -A _persisted_alias_plain=()
declare -A _persisted_alias_command=()
HOOK_PERSISTED_ALIAS_EXPS=()
# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
persisted_alias_expansions() {
  local dir="$1" sub="$2" key plain cmd q a
  printf -v q '%q' "$dir"
  key="$q"$'\n'"$sub"
  for a in ${HOOK_PROBE_LOCATING[@]+"${HOOK_PROBE_LOCATING[@]}"}; do
    printf -v q '%q' "$a"
    key+=$'\n'"$q"
  done
  if [[ -z "${_persisted_alias_plain[$key]+x}" ]]; then
    repo_git_probe "$dir" config --get "alias.$sub"
    _persisted_alias_plain["$key"]="$HOOK_REPO_GIT_PROBE_OUT"
    if [[ -z "${_persisted_alias_plain[$key]}" ]]; then
      repo_git_probe "$dir" config --get "alias.$sub.command"
      _persisted_alias_command["$key"]="$HOOK_REPO_GIT_PROBE_OUT"
    else
      _persisted_alias_command["$key"]=""
    fi
  fi
  HOOK_PERSISTED_ALIAS_EXPS=()
  plain="${_persisted_alias_plain[$key]}"
  cmd="${_persisted_alias_command[$key]}"
  [[ -n "$plain" ]] && HOOK_PERSISTED_ALIAS_EXPS+=("$plain")
  [[ -n "$cmd" ]] && HOOK_PERSISTED_ALIAS_EXPS+=("$cmd")
}

HOOK_ALIAS_WORK_MAX=128
guard::alias_depth_max

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
alias_reexpand_admit() {
  hook::git_alias_admit "$@"
  local rc=$?
  ((rc == 2)) || return "$rc"
  guard::refuse_alias_chain
  emit_tel "blocked" "alias-traversal-cap"
  exit 2
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local gi sub sub_idx nseg k word next stdin_form=0 exempt=0
  local msg_interp=0
  local inline_alias_handled=0
  local seg_dir=""
  local explicit_gd=""
  local -a locating_globals=()

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  hook::git_invocation "$@" || return 0
  gi=$HOOK_GITINV_GI
  w=("${HOOK_GITINV_WORDS[@]}")
  nseg=${#w[@]}
  sub=$HOOK_GITINV_SUB
  sub_idx=$HOOK_GITINV_SUB_IDX

  local -a wrapper_cd=()
  local wdir
  for wdir in ${HOOK_GITINV_WRAPPER_DIRS[@]+"${HOOK_GITINV_WRAPPER_DIRS[@]}"}; do
    wrapper_cd+=(-C "$wdir")
  done

  local exp reparse s seen_hit=0 saved_base=""
  local -a expw=() saved_seen=() saved_shell_seen=() nextw=()
  HOOK_FRAME_PREFIX_HAS_C=0
  local pf
  for ((pf = gi; pf < sub_idx; pf++)); do
    [[ "${w[pf]}" == "-C" ]] && HOOK_FRAME_PREFIX_HAS_C=1 && break
  done
  collect_locating_globals "${w[@]:gi:sub_idx-gi}"
  set_probe_locating
  if [[ "$HOOK_GITINV_ALIAS_TERM" == "config-env" ]]; then
    guard::refuse_config_env_alias "$sub"
    emit_tel "blocked" "config-env-alias"
    exit 2
  fi
  for s in ${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"}; do
    [[ "$s" == "$sub" ]] && {
      seen_hit=1
      break
    }
  done
  if ((seen_hit == 0)); then
    saved_seen=(${HOOK_ALIAS_SEEN[@]+"${HOOK_ALIAS_SEEN[@]}"})
    saved_shell_seen=(${HOOK_SHELL_ALIAS_SEEN[@]+"${HOOK_SHELL_ALIAS_SEEN[@]}"})
    saved_base="${HOOK_EFFECTIVE_BASE-}"
    if ((HOOK_ALIAS_DEPTH >= HOOK_ALIAS_DEPTH_MAX)); then
      guard::refuse_alias_chain
      emit_tel "blocked" "alias-depth-cap"
      exit 2
    fi
    ((++HOOK_ALIAS_DEPTH))
    HOOK_ALIAS_SEEN+=("$sub")
    if [[ "$HOOK_GITINV_ALIAS_TERM" == "inline" ]]; then
      for exp in ${HOOK_GITINV_ALIAS_EXPS[@]+"${HOOK_GITINV_ALIAS_EXPS[@]}"}; do
        [[ -n "$exp" ]] || continue
        inline_alias_handled=1
        if [[ "$exp" == '!'* ]]; then
          hook::git_alias_reparse_to reparse "$exp" "${w[@]:sub_idx+1}"
          [[ -n "$seg_dir" ]] || hook::git_effective_dir_to seg_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}"
          alias_launch_dir "$seg_dir" ${#locating_globals[@]} ||
            HOOK_ALIAS_LAUNCH_DIR="$seg_dir"
          shell_alias_reparse "$reparse"
        else
          hook::env_s_split "$exp"
          expw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
          nextw=("${w[@]:0:sub_idx}" ${expw[@]+"${expw[@]}"} "${w[@]:sub_idx+1}")
          alias_reexpand_admit git "${nextw[@]}" && check_segment "${nextw[@]}"
        fi
      done
    fi

    if ((inline_alias_handled == 0)) && [[ "$sub" != "commit" ]] &&
      ! hook::git_subcommand_ignores_alias "$sub"; then
      local pexp
      [[ -n "$seg_dir" ]] || hook::git_effective_dir_to seg_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}"
      persisted_alias_expansions "$seg_dir" "$sub"
      for pexp in ${HOOK_PERSISTED_ALIAS_EXPS[@]+"${HOOK_PERSISTED_ALIAS_EXPS[@]}"}; do
        [[ -n "$pexp" ]] || continue
        if [[ "$pexp" == '!'* ]]; then
          local pkey pseen_hit=0
          alias_launch_dir "$seg_dir" ${#locating_globals[@]} ||
            HOOK_ALIAS_LAUNCH_DIR="$seg_dir"
          pkey="$HOOK_ALIAS_LAUNCH_DIR"$'\n'"$sub="$'\n'"$pexp"
          for s in ${HOOK_SHELL_ALIAS_SEEN[@]+"${HOOK_SHELL_ALIAS_SEEN[@]}"}; do
            [[ "$s" == "$pkey" ]] && {
              pseen_hit=1
              break
            }
          done
          if ((pseen_hit == 0)); then
            HOOK_SHELL_ALIAS_SEEN+=("$pkey")
            local preparse
            hook::git_alias_reparse_to preparse "$pexp" "${w[@]:sub_idx+1}"
            shell_alias_reparse "$preparse"
          fi
        else
          local -a pexpw=()
          hook::env_s_split "$pexp"
          pexpw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
          nextw=("${w[@]:0:sub_idx}" ${pexpw[@]+"${pexpw[@]}"} "${w[@]:sub_idx+1}")
          alias_reexpand_admit git "${nextw[@]}" && check_segment "${nextw[@]}"
        fi
      done
    fi
    ((--HOOK_ALIAS_DEPTH))
    HOOK_ALIAS_SEEN=(${saved_seen[@]+"${saved_seen[@]}"})
    HOOK_SHELL_ALIAS_SEEN=(${saved_shell_seen[@]+"${saved_shell_seen[@]}"})
    HOOK_EFFECTIVE_BASE="$saved_base"
  fi

  [[ "$sub" == "commit" ]] || return 0

  for ((k = sub_idx + 1; k < nseg; k++)); do
    word="${w[k]}"
    next=""
    ((k + 1 < nseg)) && next="${w[k + 1]}"
    case "$word" in
    --)
      break
      ;;
    -F | --file)
      if [[ "$next" == "-" ]]; then stdin_form=1; else exempt=1; fi
      ((k++))
      ;;
    -F- | --file=-)
      stdin_form=1
      ;;
    --file=* | -F* | --amend | --fixup | --squash | -C | -c | --reuse-message | --reedit-message | \
      --fixup=* | --squash=* | --reuse-message=* | --reedit-message=* | -C* | -c*)
      exempt=1
      ;;
    -m | --m | --me | --mes | --mess | --messa | --messag | --message) # spellchecker:disable-line
      msg_value_interpolates "$next" && msg_interp=1
      ((k++))
      ;;
    --m=* | --me=* | --mes=* | --mess=* | --messa=* | --messag=* | --message=*) # spellchecker:disable-line
      word="${word#*=}"
      msg_value_interpolates "$word" && msg_interp=1
      ;;
    -m*)
      word="${word#-m}"
      msg_value_interpolates "$word" && msg_interp=1
      ;;
    -[!-]*m)
      msg_value_interpolates "$next" && msg_interp=1
      ((k++))
      ;;
    *)
      ;;
    esac
  done

  ((stdin_form || exempt)) && return 0
  ((msg_interp)) || return 0
  allowed "message-flag" && return 0
  [[ -n "$seg_dir" ]] || hook::git_effective_dir_to seg_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}"
  explicit_git_dir_to explicit_gd "${w[@]:gi:sub_idx-gi}"
  sequencer_in_progress "$seg_dir" "$explicit_gd" && return 0
  block_message_flag
}

block_message_flag() {
  # shellcheck disable=SC2016  # literal `$` in the message text
  {
    echo 'BLOCKED: this `git commit -m` message holds a `$` or a backtick the shell expands'
    echo 'before git sees it: `$x` and `$(...)` are replaced, and in PowerShell a backtick'
    echo 'starts an escape (`f becomes a form feed), so the message lands changed in history.'
    echo "Put it in single quotes, or pipe it via stdin: use /source-control:commit, or its"
    echo "canonical form directly:"
    if [[ "$TOOL_NAME" == "PowerShell" ]]; then
      echo "  @'"
      echo "  <subject>"
      echo "  '@ | git commit -F -"
    else
      echo "  git commit -F - --cleanup=verbatim <<'EOF'"
      echo "  <subject>"
      echo "  EOF"
    fi
    echo "Messages without \`\$\` or a backtick are allowed, multi-line included. --amend,"
    echo "-C/-c, --fixup/--squash, -F <path>, and an in-progress merge/rebase are exempt."
  } >&2
  emit_tel "blocked" "message-flag"
  exit 2
}

if [[ "$TOOL_NAME" == "PowerShell" ]]; then
  # shellcheck source=guard-requires.sh
  declare -F guard::require_libs >/dev/null || source "$_HOOK_SELF/guard-requires.sh"
  guard::require_libs
  ps::classify_git_command "$TOOL_NAME" "$COMMAND"
  ps_rc=$?
  if ((PS_REDUCTION_UNTRUSTED)); then
    PS_SINK_TRIGGER="${PS_REDUCTION_UNTRUSTED_REASON:-herestring-comment-char}"
    ps::print_unparsable_block_message "$COMMAND"
    emit_tel "blocked" "powershell-unparsable-${PS_SINK_TRIGGER}"
    exit 2
  fi
  ((ps_rc == 0)) || {
    re_commit='(^|[^[:alnum:]_-])git(\.exe)?[[:space:]]([^|;]*[[:space:]])?commit[[:space:]]'
    if ((ps_rc == 2)) && ! allowed "message-flag" && [[ "$RAW_COMMAND" =~ $re_commit ]] &&
      msg_value_interpolates ""; then
      block_message_flag
    fi
    emit_tel "ok" "powershell-deferred"
    exit 0
  }
  COMMAND="$PS_SAFE_COMMAND"
fi

HOOK_ALIAS_SEEN=()
HOOK_SHELL_ALIAS_SEEN=()
HOOK_ALIAS_DEPTH=0

HOOK_EFFECTIVE_BASE="${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}"

hook::bash_parse_segments "$COMMAND" check_segment

emit_tel "ok" ""
exit 0
