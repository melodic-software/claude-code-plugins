#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_CONVENTION_GATE_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-convention-violation PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

hook::require jq "PreToolUse" guardrails "$INPUT"

hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || exit 0

if ((HOOK_JQ_FIELDS_NUL)); then
  guard::refuse_nul
  exit 2
fi

COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
HOOK_CWD="${HOOK_JQ_FIELDS[2]}"

RESOLVER="$_HOOK_SELF/resolve-convention-pattern.sh"

SUBJECT_ERE=""
TITLE_ERE=""
SUBJECT_DIAG=""
TITLE_DIAG=""
CONV_LOADED=0

ensure_convention_patterns() {
  ((CONV_LOADED)) && return 0
  CONV_LOADED=1
  REPO_ROOT=$(hook::repo_root "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}")
  CONV_DEPS=(
    "$REPO_ROOT/docs/conventions/source-control.yaml"
    "$REPO_ROOT/docs/conventions/source-control/commit-convention.yml"
    "$REPO_ROOT/docs/conventions/source-control.local.yaml"
  )

  CONV_CACHE=""
  [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] &&
    CONV_CACHE="$CLAUDE_PLUGIN_DATA/convention-pattern/${REPO_ROOT//[^A-Za-z0-9]/_}"

  CONV_HIT=0
  # shellcheck disable=SC2094  # the entry is only READ here; the write below is a separate branch
  if [[ -n "$CONV_CACHE" && -f "$CONV_CACHE" ]]; then
    conv_root=""
    conv_subj=""
    conv_title=""
    conv_end=""
    conv_i=0
    conv_fresh=1
    {
      IFS= read -r conv_root
      IFS= read -r conv_subj
      IFS= read -r conv_title
      while IFS= read -r conv_line; do
        if [[ "$conv_line" == "END" ]]; then
          conv_end="END"
          break
        fi
        [[ "$conv_line" == "DEP "[01]" "* && "${conv_line:6}" == "${CONV_DEPS[conv_i]:-}" ]] || {
          conv_fresh=0
          break
        }
        conv_dep="${conv_line:6}"
        if [[ -e "$conv_dep" ]]; then
          [[ "${conv_line:4:1}" == 1 && "$CONV_CACHE" -nt "$conv_dep" ]] || conv_fresh=0
        else
          [[ "${conv_line:4:1}" == 0 ]] || conv_fresh=0
        fi
        ((conv_fresh)) || break
        ((conv_i++))
      done
    } <"$CONV_CACHE"
    if ((conv_fresh && conv_i == ${#CONV_DEPS[@]})) &&
      [[ "$conv_end" == "END" && "$conv_root" == "$REPO_ROOT" ]]; then
      SUBJECT_ERE="$conv_subj"
      TITLE_ERE="$conv_title"
      CONV_HIT=1
    fi
  fi

  if ((CONV_HIT == 0)) && [[ -f "$RESOLVER" ]]; then
    conv_dep_lines=""
    for conv_dep in "${CONV_DEPS[@]}"; do
      conv_exists=0
      [[ -e "$conv_dep" ]] && conv_exists=1
      conv_dep_lines+="DEP $conv_exists $conv_dep"$'\n'
    done
    { conv_errf=$(mktemp); } 2>/dev/null || conv_errf=/dev/null
    for conv_key in subject_pattern pr_title_pattern; do
      { conv_val=$(bash "$RESOLVER" "$REPO_ROOT" "$conv_key"); conv_rc=$?; } 2>"$conv_errf"
      conv_diag=""
      if ((conv_rc != 0)); then
        conv_val=""
        conv_err=""
        IFS= read -r -d '' conv_err <"$conv_errf" || true
        conv_err="${conv_err//[$'\r\n\t']/ }"
        conv_err="${conv_err#"${conv_err%%[![:space:]]*}"}"
        conv_err="${conv_err%"${conv_err##*[![:space:]]}"}"
        if [[ -n "$conv_err" || $conv_rc -ne 1 ]]; then
          conv_diag="${conv_err:0:300}"
          [[ -n "$conv_diag" ]] || conv_diag="exit status $conv_rc, no message"
        fi
      fi
      case "$conv_key" in
      subject_pattern)
        SUBJECT_ERE="$conv_val"
        SUBJECT_DIAG="$conv_diag"
        ;;
      *)
        TITLE_ERE="$conv_val"
        TITLE_DIAG="$conv_diag"
        ;;
      esac
    done
    [[ "$conv_errf" == /dev/null ]] || rm -f "$conv_errf" 2>/dev/null
    [[ -z "$SUBJECT_DIAG" && -z "$TITLE_DIAG" ]] || return 0
    if [[ -n "$CONV_CACHE" ]] && mkdir -p "${CONV_CACHE%/*}" 2>/dev/null; then
      if printf '%s\n%s\n%s\n%sEND\n' "$REPO_ROOT" "$SUBJECT_ERE" "$TITLE_ERE" "$conv_dep_lines" \
        >"$CONV_CACHE.$$" 2>/dev/null; then
        mv -f "$CONV_CACHE.$$" "$CONV_CACHE" 2>/dev/null || rm -f "$CONV_CACHE.$$" 2>/dev/null
      else
        rm -f "$CONV_CACHE.$$" 2>/dev/null
      fi
    fi
  fi
}

conv_failure_notice() {
  if hook::notice_once "guardrails-convention-resolver-$1" "$INPUT"; then
    hook::emit_skip_notice PreToolUse "guardrails block-convention-violation: the $1 convention check did not run, so this $2 was not checked. The convention resolver reported \"$3\". This notice does not repeat this session."
  fi
}

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data subject
  hook::extract_bash_subject_to subject "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$subject" form "$2"
  hook::emit_telemetry "block-convention-violation" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
first_heredoc_subject() {
  local cmd="$1" line delim="" in_hd=0 trimmed
  local start_re='(^|[^<])<<-?[[:space:]]*([^[:space:]<>]+)'
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hd)); then
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [[ "$trimmed" == "$delim" ]] && return 0
      [[ -n "$trimmed" ]] && {
        printf '%s' "${line%$'\r'}"
        return 0
      }
      continue
    fi
    if [[ "$line" =~ $start_re ]]; then
      delim="${BASH_REMATCH[2]}"
      delim="${delim#\\}"
      delim="${delim#\'}"
      delim="${delim%\'}"
      delim="${delim#\"}"
      delim="${delim%\"}"
      in_hd=1
    fi
  done < <(printf '%s\n' "$cmd") # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  return 0
}

# First non-empty line of the FIRST PowerShell here-string body (@'…'@ / @"…"@).
# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
first_herestring_subject() {
  local cmd="$1" line in_hs=0 hs_quote="" closer trimmed
  while IFS= read -r line || [[ -n "$line" ]]; do
    if ((in_hs)); then
      closer="${hs_quote}@"
      [[ "${line:0:2}" == "$closer" ]] && return 0
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      [[ -n "$trimmed" ]] && {
        printf '%s' "${line%$'\r'}"
        return 0
      }
      continue
    fi
    if ps::line_confirms_herestring_opener "$line"; then
      hs_quote="${line: -1}"
      in_hs=1
    fi
  done < <(printf '%s\n' "$cmd") # not <<<: a >=64KiB here-string deadlocks (see hardcoded-path-patterns.sh)
  return 0
}

# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
block_subject() {
  echo "BLOCKED: commit subject does not match the commit convention." >&2
  echo "  subject: $1" >&2
  echo "  pattern: $SUBJECT_ERE" >&2
  echo "Rewrite it to match the pattern above; /source-control:commit drafts against the team convention." >&2
  emit_tel "blocked" "subject-pattern"
  exit 2
}

# shellcheck disable=SC2329  # invoked from check_segment (callback chain)
block_title() {
  echo "BLOCKED: PR title does not match the team convention." >&2
  echo "  title:   $1" >&2
  echo "  pattern: $TITLE_ERE" >&2
  echo "Rewrite it to match; /source-control:pull-request drafts against the convention." >&2
  emit_tel "blocked" "pr-title-pattern"
  exit 2
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
sequencer_in_progress() {
  local dir repo="$1" f
  { dir=$(hook::git_untrusted -C "$repo" rev-parse --absolute-git-dir); } 2>/dev/null || return 1
  [[ -n "$dir" ]] || return 1
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply; do
    [[ -e "$dir/$f" ]] && return 0
  done
  return 1
}

# shellcheck disable=SC2329  # reached via the hook::bash_parse_segments callback chain
recheck_alias_expansion() {
  local exp="$1" reparse saved_base
  local -a expw=()
  if [[ "$exp" == '!'* ]]; then
    hook::git_alias_reparse_to reparse "$exp" "${w[@]:sub_idx+1}"
    [[ -n "$seg_dir" ]] ||
      hook::git_effective_dir_to seg_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}"
    saved_base="${HOOK_EFFECTIVE_BASE:-}"
    HOOK_EFFECTIVE_BASE="$seg_dir"
    hook::bash_parse_segments "$reparse" check_segment
    HOOK_EFFECTIVE_BASE="$saved_base"
  else
    hook::env_s_split "$exp"
    expw=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"})
    HOOK_NO_ALIAS=1
    check_segment "${w[@]:0:sub_idx}" ${expw[@]+"${expw[@]}"} "${w[@]:sub_idx+1}"
    HOOK_NO_ALIAS=0
  fi
}

# shellcheck disable=SC2329  # invoked indirectly as the hook::bash_parse_segments callback
check_segment() {
  local -a w=()
  local gi sub sub_idx nseg k word next stdin_form=0 exempt=0

  if hook::shell_c_operand "$@"; then
    hook::bash_parse_segments "$HOOK_SHELL_C_OPERAND" check_segment
    return 0
  fi

  local -a gw=("$@")
  local gn=$# gs=0 gt
  while ((gs < gn)); do
    gt="${gw[gs]}"
    if [[ "$gt" == *=* && "$gt" != -* ]]; then
      ((gs++))
      continue
    fi
    case "${gt##*/}" in
    env | command)
      ((gs++))
      while ((gs < gn)) && [[ "${gw[gs]}" == -* || ("${gw[gs]}" == *=* && "${gw[gs]}" != -*) ]]; do ((gs++)); done
      continue
      ;;
    *) break ;;
    esac
  done
  if [[ "${gw[gs]:-}" == "gh" && "${gw[gs + 1]:-}" == "pr" && "${gw[gs + 2]:-}" == "create" ]]; then
    ensure_convention_patterns
    if [[ -n "$TITLE_ERE" || -n "$TITLE_DIAG" ]]; then
      local t="" ti
      for ((ti = gs + 3; ti < gn; ti++)); do
        case "${gw[ti]}" in
        --title | -t)
          ((ti + 1 < gn)) && t="${gw[ti + 1]}"
          ;;
        --title=*)
          t="${gw[ti]#--title=}"
          ;;
        *) ;;
        esac
      done
      if [[ -n "$t" && -n "$TITLE_DIAG" ]]; then
        conv_failure_notice "PR-title" "PR title" "$TITLE_DIAG"
      elif [[ -n "$t" ]] && ! [[ "$t" =~ $TITLE_ERE ]]; then
        block_title "$t"
      fi
    fi
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

  local seg_dir=""

  local exp inline_alias_handled=0
  [[ "$HOOK_GITINV_ALIAS_TERM" == "config-env" ]] && return 0
  if ((${HOOK_NO_ALIAS:-0} == 0)); then
    if [[ "$HOOK_GITINV_ALIAS_TERM" == "inline" ]]; then
      for exp in ${HOOK_GITINV_ALIAS_EXPS[@]+"${HOOK_GITINV_ALIAS_EXPS[@]}"}; do
        [[ -n "$exp" ]] || continue
        inline_alias_handled=1
        recheck_alias_expansion "$exp"
      done
    fi
    if ((inline_alias_handled == 0)) && [[ "$sub" != "commit" ]] &&
      ! hook::git_subcommand_ignores_alias "$sub"; then
      local pexp
      [[ -n "$seg_dir" ]] ||
        hook::git_effective_dir_to seg_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}"
      { pexp=$(hook::git_untrusted -C "$seg_dir" config --get "alias.$sub"); } 2>/dev/null
      [[ -n "$pexp" ]] && recheck_alias_expansion "$pexp"
    fi
  fi

  [[ "$sub" == "commit" ]] || return 0
  ensure_convention_patterns
  if [[ -n "$SUBJECT_DIAG" ]]; then
    conv_failure_notice "commit-subject" "commit subject" "$SUBJECT_DIAG"
    return 0
  fi
  [[ -n "$SUBJECT_ERE" ]] || return 0
  [[ -n "$seg_dir" ]] ||
    hook::git_effective_dir_to seg_dir ${wrapper_cd[@]+"${wrapper_cd[@]}"} "${w[@]:gi:sub_idx-gi}"

  for ((k = sub_idx + 1; k < nseg; k++)); do
    word="${w[k]}"
    next=""
    ((k + 1 < nseg)) && next="${w[k + 1]}"
    case "$word" in
    --) break ;;
    -F | --file)
      if [[ "$next" == "-" ]]; then stdin_form=1; else exempt=1; fi
      ((k++))
      ;;
    -F- | --file=-) stdin_form=1 ;;
    --file=* | -F*) exempt=1 ;;
    --amend | --fixup | --squash | -C | -c | --reuse-message | --reedit-message) exempt=1 ;;
    --fixup=* | --squash=* | --reuse-message=* | --reedit-message=*) exempt=1 ;;
    -C* | -c*) exempt=1 ;;
    *) ;;
    esac
  done

  ((stdin_form)) || return 0
  ((exempt)) && return 0
  sequencer_in_progress "$seg_dir" && return 0

  local subj=""
  if [[ "$TOOL_NAME" == "PowerShell" ]]; then
    subj=$(first_herestring_subject "$COMMAND")
  else
    subj=$(first_heredoc_subject "$COMMAND")
  fi
  [[ -n "$subj" ]] || return 0

  [[ "$subj" =~ $SUBJECT_ERE ]] || block_subject "$subj"
  return 0
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
    emit_tel "ok" ""
    exit 0
  }
  hook::bash_parse_segments "$PS_SAFE_COMMAND" check_segment
else
  hook::bash_parse_segments "$COMMAND" check_segment
fi

emit_tel "ok" ""
exit 0
