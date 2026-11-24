#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_BODY_FORMAT_VIOLATION_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-body-format-violation PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70
# shellcheck source=../lib/github-post/github-post-body.sh
source "${CLAUDE_PLUGIN_ROOT:-$_HOOK_SELF/..}/lib/github-post/github-post-body.sh" || exit 70

start=${EPOCHREALTIME:-}
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
hook::require_jq_blocking "guardrails-block-body-format-violation" "block_body_format_violation_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || jq_rc=$?
guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))
COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
_BFV_CWD="${HOOK_JQ_FIELDS[2]:-$PWD}"

MAX_COMMAND_LEN=16384
_BFV_TEAM_REL="docs/conventions/source-control.yaml"
_BFV_LOCAL_REL="docs/conventions/source-control.local.yaml"
_BFV_FORM=""
_BFV_TARGET=""
_BFV_BODY=""

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" form "$_BFV_FORM"
  hook::emit_telemetry "block-body-format-violation" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

_bfv_slug_to() {
  local -n __bfv_slug="$1"
  local s="${2,,}"
  s="${s%/}"
  s="${s%.git}"
  s="${s//:/\/}"
  local repo="${s##*/}"
  s="${s%/*}"
  __bfv_slug="${s##*/}/$repo"
  [[ "$__bfv_slug" =~ ^[a-z0-9_.-]+/[a-z0-9_.-]+$ ]]
}

_bfv_body_from_file() {
  local i
  ((${#GHPOST_WTARGETS[@]})) && return 1
  [[ "$1" == *[\$\`]* ]] && return 1
  for i in "${!GHPOST_BODY[@]}"; do
    if [[ "${GHPOST_BODY_KIND[i]}" == file && "${GHPOST_BODY_SRC[i]}" == "$1" ]]; then
      _BFV_BODY="${GHPOST_BODY[i]}"
      return 0
    fi
  done
  return 1
}

_bfv_body_from_word() {
  local v="$1" line delim="" out="" started=0
  local re_doc="^\\\$\\(cat[[:space:]]*<<-?[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)['\"]?[[:space:]]*$"
  local re_cat='^\$\((cat[[:space:]]+|<[[:space:]]*)([^)[:space:]]+)\)$'
  if [[ "${v%%$'\n'*}" =~ $re_doc ]]; then
    delim="${BASH_REMATCH[1]}"
    while IFS= read -r line; do
      if ((! started)); then
        started=1
        continue
      fi
      [[ "${line#"${line%%[![:space:]]*}"}" == "$delim" ]] && {
        _BFV_BODY="$out"
        return 0
      }
      out+="$line"$'\n'
    done <<<"$v"
    return 1
  fi
  if [[ "$v" =~ $re_cat ]]; then
    _bfv_body_from_file "${BASH_REMATCH[2]}"
    return
  fi
  [[ "$v" == *[\$\`]* ]] && return 1
  _BFV_BODY="$v"
  return 0
}

_bfv_body() {
  local i n=${#GHPOST_TEXTS[@]} w kind="" val="" given=0
  for ((i = 0; i < n; i++)); do
    w="${GHPOST_TEXTS[i]}"
    case "$w" in
    --body | -b) kind=word val="${GHPOST_TEXTS[i + 1]-}" given=$((i + 1 < n)) ;;
    --body=*) kind=word val="${w#--body=}" given=1 ;;
    -b?*) kind=word val="${w#-b}" ;;
    --body-file | -F) kind=file val="${GHPOST_TEXTS[i + 1]-}" ;;
    --body-file=*) kind=file val="${w#--body-file=}" ;;
    -F?*) kind=file val="${w#-F}" ;;
    *) continue ;;
    esac
    break
  done
  [[ -n "$kind" ]] || return 1
  if [[ -z "$val" ]]; then
    [[ "$kind" == word && "$_BFV_FORM" == issue-create ]] && ((given)) || return 1
    _BFV_BODY=""
    return 0
  fi
  ghpost::bodies
  if [[ "$kind" == word ]]; then
    _bfv_body_from_word "$val"
    return
  fi
  if [[ "$val" == - ]]; then
    ghpost::heredocs
    ((${#GHPOST_HEREDOCS[@]} == 1)) || return 1
    _BFV_BODY="${GHPOST_HEREDOCS[0]%$'\n'}"
    _BFV_BODY="${_BFV_BODY%"${_BFV_BODY##*$'\n'}"}"
    return 0
  fi
  _bfv_body_from_file "$val"
}

_bfv_bash() {
  [[ "$TOOL_NAME" == Bash && -n "$COMMAND" ]] || exit 0
  ((${#COMMAND} <= MAX_COMMAND_LEN)) || exit 0
  local re_gh='(^|[^a-z0-9_.-])gh(\.exe)?[[:space:]]'
  [[ "${COMMAND,,}" =~ $re_gh ]] || exit 0
  [[ "$COMMAND" == *create* || "$COMMAND" == *edit* ]] || exit 0
  local re_cd='(^|[;&|({]|'$'\n'')[[:space:]]*((builtin|command)[[:space:]]+)?(cd|pushd|popd)([[:space:]]|$)'
  [[ "$COMMAND" =~ $re_cd ]] && exit 0
  ghpost::collect "$COMMAND" "$_BFV_CWD" "$TOOL_NAME"
  case "$GHPOST_POST" in
  gh-pr-create) _BFV_FORM=pr-create ;;
  gh-pr-edit) _BFV_FORM=pr-edit ;;
  gh-issue-create) _BFV_FORM=issue-create ;;
  *) exit 0 ;;
  esac
  local re_repo='(^|[[:space:]])(-R|--repo)(=|[[:space:]]+)?([^[:space:];&|)]+)'
  if [[ "$COMMAND" =~ $re_repo ]]; then
    local r="${BASH_REMATCH[4]}"
    r="${r//[\"\']/}"
    _bfv_slug_to _BFV_TARGET "$r" || exit 0
  fi
  local i w u re_url='^https?://[^/[:space:]]+/([^/[:space:]]+/[^/[:space:]]+)/pull/[0-9]+/?([?#].*)?$'
  for ((i = 0; i < ${#GHPOST_TEXTS[@]}; i++)); do
    w="${GHPOST_TEXTS[i]}"
    [[ "$w" =~ $re_url ]] || continue
    case "${GHPOST_TEXTS[i - 1]-}" in
    -b | --body | -t | --title) continue ;;
    *) ;;
    esac
    _bfv_slug_to u "${BASH_REMATCH[1]}" || exit 0
    [[ -z "$_BFV_TARGET" || "$_BFV_TARGET" == "$u" ]] || exit 0
    _BFV_TARGET="$u"
  done
  _bfv_body || exit 0
}

_bfv_mcp() {
  case "$TOOL_NAME" in
  *__create_pull_request) _BFV_FORM=pr-create ;;
  *__update_pull_request) _BFV_FORM=pr-edit ;;
  *__create_issue | *__issue_write) _BFV_FORM=issue-create ;;
  *) exit 0 ;;
  esac
  jq_rc=0
  hook::jq_fields "$INPUT" '.tool_input.body' '.tool_input.owner' '.tool_input.repo' '.tool_input.method' || jq_rc=$?
  guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))
  [[ "$TOOL_NAME" != *__issue_write || "${HOOK_JQ_FIELDS[3]}" == create ]] || exit 0
  _BFV_BODY="${HOOK_JQ_FIELDS[0]}"
  [[ -n "$_BFV_BODY" || "$_BFV_FORM" == issue-create ]] || exit 0
  _bfv_slug_to _BFV_TARGET "${HOOK_JQ_FIELDS[1]}/${HOOK_JQ_FIELDS[2]}" || exit 0
}

if [[ "$TOOL_NAME" == mcp__* ]]; then
  _bfv_mcp
else
  _bfv_bash
fi

_BFV_ROOT=""
hook::repo_root_to _BFV_ROOT "$_BFV_CWD" || exit 0
[[ "$HOME/" == "$_BFV_ROOT/"* ]] && exit 0
_bfv_git() { hook::git_untrusted -C "$_BFV_ROOT" "$@"; }

_bfv_origin=$(_bfv_git remote get-url origin 2>/dev/null) || _bfv_origin=""
_bfv_slug_to _BFV_SELF "$_bfv_origin" || _BFV_SELF=""
[[ -n "$_BFV_SELF" ]] || exit 0
[[ -z "$_BFV_TARGET" || "$_BFV_TARGET" == "$_BFV_SELF" ]] || exit 0

_bfv_note() { printf 'guardrails: block-body-format-violation: %s\n' "$1" >&2; }

_bfv_records_to() {
  local -n __bfv_rec="$1"
  __bfv_rec=""
  [[ -f "$_BFV_ROOT/$2" ]] || return 1
  if [[ "$3" == team ]]; then
    _bfv_git ls-files --error-unmatch -- "$2" >/dev/null 2>&1 || return 1
  else
    _bfv_git check-ignore -q -- "$2" >/dev/null 2>&1 || {
      _bfv_note "$2 is not ignored by git, so it is not read as the personal override."
      return 1
    }
  fi
  if ! __bfv_rec=$(LC_ALL=C awk -v STRICT=1 -f "$_HOOK_SELF/yaml-subset.awk" <"$_BFV_ROOT/$2" 2>/dev/null); then
    _bfv_note "$2 does not parse; it is not read."
    __bfv_rec=""
    return 1
  fi
  __bfv_rec=$'\n'"$__bfv_rec"$'\n'
}

_bfv_records_to _BFV_TEAM "$_BFV_TEAM_REL" team || true
_bfv_records_to _BFV_LOCAL "$_BFV_LOCAL_REL" local || true
[[ -n "$_BFV_TEAM$_BFV_LOCAL" ]] || exit 0

_bfv_key() {
  local rec layer rel
  _BFV_VAL=()
  _BFV_LAYER=""
  for layer in LOCAL TEAM; do
    local -n __bfv_r="_BFV_$layer"
    rel="$_BFV_TEAM_REL"
    [[ "$layer" == LOCAL ]] && rel="$_BFV_LOCAL_REL"
    if [[ "$__bfv_r" == *$'\n'"$1"$'\t'* ]]; then
      rec="${__bfv_r#*$'\n'"$1"$'\t'}"
      _BFV_VAL=("${rec%%$'\n'*}")
    elif [[ "$__bfv_r" == *$'\n'"$1".0$'\t'* ]]; then
      local i=0
      while [[ "$__bfv_r" == *$'\n'"$1.$i"$'\t'* ]]; do
        rec="${__bfv_r#*$'\n'"$1.$i"$'\t'}"
        _BFV_VAL+=("${rec%%$'\n'*}")
        i=$((i + 1))
      done
    fi
    unset -n __bfv_r
    if ((${#_BFV_VAL[@]})); then
      _BFV_LAYER="$rel"
      return 0
    fi
  done
  return 1
}

_bfv_trim_to() {
  local -n __bfv_t="$1"
  __bfv_t="${2#"${2%%[![:space:]]*}"}"
  __bfv_t="${__bfv_t%"${__bfv_t##*[![:space:]]}"}"
}

_bfv_gate() {
  _bfv_key "$1" || return 0
  case "${_BFV_VAL[0]}" in
  false) exit 0 ;;
  true) ;;
  *) _bfv_note "$_BFV_LAYER sets $1: '${_BFV_VAL[0]}', not true or false; the gate stays on." ;;
  esac
}

_bfv_prepare_lines() {
  local text="${_BFV_BODY//$'\r'/}" rest i l fence=""
  local re_fence='^ {0,3}(`{3,}|~{3,})(.*)$'
  while [[ "$text" == *'<!--'* ]]; do
    rest="${text#*<!--}"
    if [[ "$rest" == *'-->'* ]]; then
      text="${text%%<!--*}${rest#*-->}"
    else
      text="${text%%<!--*}"
    fi
  done
  mapfile -t _BFV_LINES <<<"$text"
  for i in "${!_BFV_LINES[@]}"; do
    l="${_BFV_LINES[i]}"
    if [[ -z "$fence" ]]; then
      [[ "$l" =~ $re_fence ]] || continue
      [[ "${BASH_REMATCH[1]:0:1}" == '`' && "${BASH_REMATCH[2]}" == *'`'* ]] && continue
      fence="${BASH_REMATCH[1]}"
    elif [[ "$l" =~ $re_fence && "${BASH_REMATCH[1]:0:1}" == "${fence:0:1}" &&
      ${#BASH_REMATCH[1]} -ge ${#fence} && "${BASH_REMATCH[2]}" =~ ^[[:space:]]*$ ]]; then
      fence=""
    fi
    _BFV_LINES[i]=""
  done
}

_bfv_check_heads() {
  local mode="$1" maxlvl=2 h i t lvl hl start slvl has mark="##" re_head='^(#+)[[:space:]]+(.*)$' re_any='^(#+)[[:space:]]'
  shift
  local all
  printf -v all '\n%s' "$@"
  if [[ "$mode" == issue ]]; then
    maxlvl=3
    mark="###"
  fi
  for h in "$@"; do
    start=-1
    for i in "${!_BFV_LINES[@]}"; do
      _bfv_trim_to t "${_BFV_LINES[i]}"
      [[ "$t" =~ $re_head ]] || continue
      lvl=${#BASH_REMATCH[1]}
      ((lvl >= 2 && lvl <= maxlvl)) || continue
      hl="${BASH_REMATCH[2]}"
      hl="${hl%"${hl##*[!#[:space:]]}"}"
      if [[ "${hl,,}" == "${h,,}" ]]; then
        start=$((i + 1))
        slvl=$lvl
        break
      fi
    done
    if ((start < 0)); then
      if [[ "$mode" == issue ]]; then
        _BFV_PROBLEMS+=("Missing a \"$mark $h\" heading: add \"$mark $h\" (or \"## $h\") with its answer under it.")
      else
        _BFV_PROBLEMS+=("Missing a \"## $h\" section: add the heading \"## $h\" with its content under it.")
      fi
      continue
    fi
    has=0
    for ((i = start; i < ${#_BFV_LINES[@]}; i++)); do
      _bfv_trim_to t "${_BFV_LINES[i]}"
      if [[ "$t" =~ $re_any ]]; then
        ((${#BASH_REMATCH[1]} <= slvl)) && break
        if [[ "$mode" == issue ]]; then
          [[ "$t" =~ $re_head ]] || continue
          hl="${BASH_REMATCH[2]}"
          hl="${hl%"${hl##*[!#[:space:]]}"}"
          [[ "${all,,}"$'\n' == *$'\n'"${hl,,}"$'\n'* ]] && break
          continue
        fi
      fi
      [[ -z "$t" ]] && continue
      [[ "$mode" == issue && "$t" == "_No response_" ]] && continue
      has=1
      break
    done
    if ((! has)); then
      if [[ "$mode" == issue ]]; then
        _BFV_PROBLEMS+=("The \"$mark $h\" heading is empty or answered _No response_: write its answer under the heading.")
      else
        _BFV_PROBLEMS+=("The \"## $h\" section is empty: write its content under the heading.")
      fi
    fi
  done
}

_bfv_issue_kinds() {
  local key=issue_body_required_sections layer rel line rest kind idx bad=0
  _BFV_KINDS=()
  declare -gA _BFV_KIND_HEADS=()
  for layer in LOCAL TEAM; do
    local -n __bfv_k="_BFV_$layer"
    rel="$_BFV_TEAM_REL"
    [[ "$layer" == LOCAL ]] && rel="$_BFV_LOCAL_REL"
    if [[ "$__bfv_k" == *$'\n'"$key"$'\t'* ]]; then
      rest="${__bfv_k#*$'\n'"$key"$'\t'}"
      rest="${rest%%$'\n'*}"
      [[ "$rest" == none ]] ||
        _bfv_note "$rel sets $key: '$rest', not a mapping of issue kinds or none; no issue format is applied."
      return 1
    fi
    if [[ "$__bfv_k" == *$'\n'"$key".* ]]; then
      while IFS= read -r line; do
        [[ "$line" == "$key".*$'\t'* ]] || continue
        rest="${line%%$'\t'*}"
        rest="${rest#"$key".}"
        kind="${rest%.*}"
        idx="${rest##*.}"
        [[ "$idx" =~ ^[0-9]+$ ]] || continue
        if [[ ! "$kind" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
          ((bad++)) || _bfv_note "$rel names an issue kind that is not a lowercase id (^[a-z0-9][a-z0-9-]*\$); that kind is skipped."
          continue
        fi
        [[ -n "${_BFV_KIND_HEADS[$kind]+x}" ]] || _BFV_KINDS+=("$kind")
        _BFV_KIND_HEADS[$kind]+="${line#*$'\t'}"$'\n'
      done <<<"$__bfv_k"
      _BFV_ISSUE_SRC="$key in $rel"
      return $((${#_BFV_KINDS[@]} == 0))
    fi
    unset -n __bfv_k
  done
  return 1
}

_BFV_PROBLEMS=()

if [[ "$_BFV_FORM" == issue-create ]]; then
  _bfv_gate issue_body_format_gate
  _bfv_issue_kinds || exit 0
  _bfv_prepare_lines
  _bfv_best=""
  _bfv_best_p=()
  for _bfv_kind in "${_BFV_KINDS[@]}"; do
    _BFV_PROBLEMS=()
    mapfile -t _bfv_heads <<<"${_BFV_KIND_HEADS[$_bfv_kind]%$'\n'}"
    _bfv_check_heads issue "${_bfv_heads[@]}"
    if ((${#_BFV_PROBLEMS[@]} == 0)); then
      emit_tel ok
      exit 0
    fi
    if [[ -z "$_bfv_best" ]] || ((${#_BFV_PROBLEMS[@]} < ${#_bfv_best_p[@]})); then
      _bfv_best="$_bfv_kind"
      _bfv_best_p=("${_BFV_PROBLEMS[@]}")
    fi
  done
  {
    printf 'BLOCKED: this issue body matches none of the issue kinds %s declares (%s: %s).\n' "$_BFV_SELF" "$_BFV_ISSUE_SRC" "${_BFV_KINDS[*]}"
    _bfv_list="${_BFV_KIND_HEADS[$_bfv_best]%$'\n'}"
    printf 'Closest kind, %s, requires: %s.\n' "$_bfv_best" "${_bfv_list//$'\n'/, }"
    printf -- '- %s\n' "${_bfv_best_p[@]}"
    printf 'Fix the body and run the command again. To turn this gate off for the repository, set issue_body_format_gate: false in %s (or, for yourself only, in %s).\n' "$_BFV_TEAM_REL" "$_BFV_LOCAL_REL"
  } >&2
  emit_tel blocked
  exit 2
fi

_bfv_gate pr_body_format_gate

_BFV_SECTIONS=()
_BFV_SECTIONS_SRC=""
if _bfv_key pr_body_required_sections; then
  _BFV_SECTIONS_SRC="pr_body_required_sections in $_BFV_LAYER"
  case "${#_BFV_VAL[@]}:${_BFV_VAL[0]}" in
  1:none) _BFV_SECTIONS_SRC="" ;;
  1:briefing) _BFV_SECTIONS=(Why "What changed" Scope Verification) ;;
  1:summary-test-plan) _BFV_SECTIONS=(Summary "Test plan") ;;
  *) _BFV_SECTIONS=("${_BFV_VAL[@]}") ;;
  esac
fi

_BFV_OPENER_SRC=""
if _bfv_key linkage_gate_uses_pattern; then
  _bfv_pat="${_BFV_VAL[0]}"
  _bfv_wf=()
  for _bfv_f in "$_BFV_ROOT"/.github/workflows/*.yml "$_BFV_ROOT"/.github/workflows/*.yaml; do
    [[ -f "$_bfv_f" ]] && _bfv_wf+=("$_bfv_f")
  done
  if ((${#_bfv_wf[@]})); then
    _bfv_hit=$(grep -lE -m1 -- "$_bfv_pat" "${_bfv_wf[@]}" 2>/dev/null)
    _bfv_rc=$?
    if ((_bfv_rc == 0)); then
      _bfv_hit="${_bfv_hit%%$'\n'*}"
      _BFV_OPENER_SRC="linkage_gate_uses_pattern in $_BFV_LAYER, matched by ${_bfv_hit#"$_BFV_ROOT/"}"
    elif ((_bfv_rc > 1)); then
      _bfv_note "linkage_gate_uses_pattern in $_BFV_LAYER does not compile as an extended regular expression; the opener rule is not applied."
    fi
  fi
fi

_BFV_LOOSE_SRC=""
if _bfv_key pr_body_loosened_checks_heading; then
  _bfv_lh="${_BFV_VAL[0]}"
  _bfv_llayer="$_BFV_LAYER"
  _bfv_lp=""
  _bfv_lm=""
  _bfv_key pr_body_loosened_checks_record_pattern && _bfv_lp="${_BFV_VAL[0]}"
  _bfv_key pr_body_loosened_checks_verbatim_marker && _bfv_lm="${_BFV_VAL[0]}"
  if [[ -z "$_bfv_lp" || -z "$_bfv_lm" ]]; then
    _bfv_note "$_bfv_llayer sets pr_body_loosened_checks_heading without both pr_body_loosened_checks_record_pattern and pr_body_loosened_checks_verbatim_marker; the Loosened checks rule is not applied."
  else
    [[ "" =~ $_bfv_lp ]]
    _bfv_rc=$?
    if ((_bfv_rc > 1)); then
      _bfv_note "pr_body_loosened_checks_record_pattern does not compile as an extended regular expression; the Loosened checks rule is not applied."
    else
      _BFV_LOOSE_SRC="pr_body_loosened_checks_heading in $_bfv_llayer"
    fi
  fi
fi

[[ -n "$_BFV_SECTIONS_SRC$_BFV_OPENER_SRC$_BFV_LOOSE_SRC" ]] || exit 0

_bfv_has_verbatim() {
  local t="${1,,}" m="${2,,}" rest
  while [[ "$t" == *"$m"* ]]; do
    rest="${t#*"$m"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [[ "$rest" == \"[!\"]*\"* ]] && return 0
    t="$rest"
  done
  return 1
}

_bfv_add_ref() {
  local repo="${1:-$_BFV_SELF}" ref
  [[ "$repo" =~ ^[a-z0-9_-][a-z0-9_.-]*/[a-z0-9_-][a-z0-9_.-]*$ ]] || return 0
  ref="$repo#$2"
  [[ "$_bfv_lseen" == *$'\n'"$ref"$'\n'* ]] && return 0
  _bfv_lseen+="$ref"$'\n'
  _BFV_LREFS+=("$ref")
}

_bfv_collect_refs() {
  local l t m
  local kw='(close[sd]?|fix(es|ed)?|resolve[sd]?)'
  local repo='([a-z0-9_.-]+/[a-z0-9_.-]+)'
  local re_close="(^|[^a-z0-9_])$kw:?[[:space:]]+$repo?#([0-9]+)"
  local re_refs="(^|[^a-z0-9_])(refs|relates to):[[:space:]]*$repo?#([0-9]+)"
  local re_url="(^|[^a-z0-9_])($kw|refs|relates to):?[[:space:]]+https?://github\\.com/$repo/issues/([0-9]+)"
  _BFV_LREFS=()
  _bfv_lseen=$'\n'
  for l in "${_BFV_LINES[@]}"; do
    t="${l,,}"
    while [[ "$t" =~ $re_url ]]; do
      m="${BASH_REMATCH[0]}"
      _bfv_add_ref "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
      t="${t#*"$m"}"
    done
    t="${l,,}"
    while [[ "$t" =~ $re_close ]]; do
      m="${BASH_REMATCH[0]}"
      _bfv_add_ref "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}"
      t="${t#*"$m"}"
    done
    t="${l,,}"
    while [[ "$t" =~ $re_refs ]]; do
      m="${BASH_REMATCH[0]}"
      _bfv_add_ref "${BASH_REMATCH[3]}" "${BASH_REMATCH[4]}"
      t="${t#*"$m"}"
    done
  done
}

_bfv_issue_body_to() {
  local -n __bfv_ib="$1"
  local repo="${2%#*}" num="${2##*#}" out rc=0
  if command -v timeout >/dev/null 2>&1; then
    out=$(GH_PROMPT_DISABLED=1 timeout 10 gh api "repos/$repo/issues/$num" --jq '.body // ""' 2>/dev/null) || rc=$?
  else
    out=$(GH_PROMPT_DISABLED=1 gh api "repos/$repo/issues/$num" --jq '.body // ""' 2>/dev/null) || rc=$?
  fi
  __bfv_ib="$out"
  return "$rc"
}

_bfv_loosened_check() {
  local saved=(${_BFV_PROBLEMS[@]+"${_BFV_PROBLEMS[@]}"}) ref body n=0 missing link verb
  local h="## $_bfv_lh"
  _BFV_PROBLEMS=()
  _bfv_check_heads pr "$_bfv_lh"
  if ((${#_BFV_PROBLEMS[@]})); then
    _BFV_PROBLEMS=(${saved[@]+"${saved[@]}"})
    return 0
  fi
  _BFV_PROBLEMS=(${saved[@]+"${saved[@]}"})
  _bfv_collect_refs
  if ((${#_BFV_LREFS[@]} == 0)); then
    _BFV_PROBLEMS+=("The \"$h\" section is not empty, but the body links no issue. Link the issue that records the owner's decision with \`Closes #<issue>\` (or Fixes, Resolves) or \`Refs: #<issue>\`; its body, not this PR body, must hold a line link to the decision record and the owner's words after \`$_bfv_lm\` in double quotes ($_BFV_LOOSE_SRC).")
    return 0
  fi
  local -a found=() refs=("${_BFV_LREFS[@]:0:3}") pids=()
  local dir
  dir=$(mktemp -d 2>/dev/null) || {
    _bfv_note "could not make a temporary directory, so the \"$h\" authorization is not checked here; pr-verify still checks it."
    return 0
  }
  for ref in "${refs[@]}"; do
    (
      if _bfv_issue_body_to body "$ref"; then
        printf '%s' "$body" >"$dir/$n"
      else
        : >"$dir/$n.err"
      fi
    ) &
    pids+=("$!")
    n=$((n + 1))
  done
  wait "${pids[@]}"
  n=0
  for ref in "${refs[@]}"; do
    if [[ ! -f "$dir/$n" ]]; then
      rm -rf "${dir:?}"
      _bfv_note "could not read issue $ref, so the \"$h\" authorization is not checked here; pr-verify still checks it."
      return 0
    fi
    body=$(<"$dir/$n")
    n=$((n + 1))
    link=0
    verb=0
    [[ "$body" =~ $_bfv_lp ]] && link=1
    _bfv_has_verbatim "$body" "$_bfv_lm" && verb=1
    if ((link && verb)); then
      rm -rf "${dir:?}"
      return 0
    fi
    missing=""
    ((link)) || missing="a line link to the owner-decisions record (matching pr_body_loosened_checks_record_pattern)"
    ((verb)) || missing+="${missing:+ and }the owner's words after \`$_bfv_lm\` in double quotes"
    found+=("Issue $ref does not authorize the \"$h\" section: its body lacks $missing. Add it to the issue's body, not the PR body.")
  done
  rm -rf "${dir:?}"
  _BFV_PROBLEMS+=("${found[@]}")
}

_bfv_prepare_lines

if [[ -n "$_BFV_OPENER_SRC" ]]; then
  _bfv_first=""
  for _bfv_l in "${_BFV_LINES[@]}"; do
    _bfv_trim_to _bfv_first "$_bfv_l"
    [[ -n "$_bfv_first" ]] && break
  done
  _bfv_ref='(([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)?#[0-9]+|https?://[^[:space:]]+/(issues|pull)/[0-9]+)'
  _bfv_re_open="^((close[sd]?|fix(es|ed)?|resolve[sd]?):?[[:space:]]+$_bfv_ref|(refs|relates to):[[:space:]]*$_bfv_ref|(no related issue|no linked issue):[[:space:]]*[^[:space:]])"
  if [[ ! "${_bfv_first,,}" =~ $_bfv_re_open ]]; then
    _BFV_PROBLEMS+=("The body does not open with a linkage line ($_BFV_OPENER_SRC). Make its first line one of: \`Closes #<issue>\` (or Fixes, Resolves), \`Refs: #<issue>\`, or \`No related issue: <reason>\`.")
  fi
fi

_bfv_check_heads pr ${_BFV_SECTIONS[@]+"${_BFV_SECTIONS[@]}"}
[[ -n "$_BFV_LOOSE_SRC" ]] && _bfv_loosened_check

if ((${#_BFV_PROBLEMS[@]} == 0)); then
  emit_tel ok
  exit 0
fi

{
  printf 'BLOCKED: this pull request body breaks the body format %s declares:\n' "$_BFV_SELF"
  if [[ -n "$_BFV_SECTIONS_SRC" ]]; then
    _bfv_list=""
    for _bfv_h in "${_BFV_SECTIONS[@]}"; do _bfv_list+="${_bfv_list:+, }$_bfv_h"; done
    printf 'Required sections (%s): %s.\n' "$_BFV_SECTIONS_SRC" "$_bfv_list"
  fi
  printf -- '- %s\n' "${_BFV_PROBLEMS[@]}"
  printf 'Fix the body and run the command again. To turn this gate off for the repository, set pr_body_format_gate: false in %s (or, for yourself only, in %s).\n' "$_BFV_TEAM_REL" "$_BFV_LOCAL_REL"
} >&2
emit_tel blocked
exit 2
