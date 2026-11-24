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
  local i n=${#GHPOST_TEXTS[@]} w kind="" val=""
  for ((i = 0; i < n; i++)); do
    w="${GHPOST_TEXTS[i]}"
    case "$w" in
    --body | -b) kind=word val="${GHPOST_TEXTS[i + 1]-}" ;;
    --body=*) kind=word val="${w#--body=}" ;;
    -b?*) kind=word val="${w#-b}" ;;
    --body-file | -F) kind=file val="${GHPOST_TEXTS[i + 1]-}" ;;
    --body-file=*) kind=file val="${w#--body-file=}" ;;
    -F?*) kind=file val="${w#-F}" ;;
    *) continue ;;
    esac
    break
  done
  [[ -n "$kind" && -n "$val" ]] || return 1
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
  *) exit 0 ;;
  esac
  jq_rc=0
  hook::jq_fields "$INPUT" '.tool_input.body' '.tool_input.owner' '.tool_input.repo' || jq_rc=$?
  guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))
  _BFV_BODY="${HOOK_JQ_FIELDS[0]}"
  [[ -n "$_BFV_BODY" ]] || exit 0
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

if _bfv_key pr_body_format_gate; then
  case "${_BFV_VAL[0]}" in
  false) exit 0 ;;
  true) ;;
  *) _bfv_note "$_BFV_LAYER sets pr_body_format_gate: '${_BFV_VAL[0]}', not true or false; the gate stays on." ;;
  esac
fi

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

[[ -n "$_BFV_SECTIONS_SRC$_BFV_OPENER_SRC" ]] || exit 0

_bfv_text="${_BFV_BODY//$'\r'/}"
while [[ "$_bfv_text" == *'<!--'* ]]; do
  _bfv_rest="${_bfv_text#*<!--}"
  if [[ "$_bfv_rest" == *'-->'* ]]; then
    _bfv_text="${_bfv_text%%<!--*}${_bfv_rest#*-->}"
  else
    _bfv_text="${_bfv_text%%<!--*}"
  fi
done
mapfile -t _BFV_LINES <<<"$_bfv_text"
_bfv_fence=""
_bfv_re_fence='^ {0,3}(`{3,}|~{3,})(.*)$'
for _bfv_i in "${!_BFV_LINES[@]}"; do
  _bfv_l="${_BFV_LINES[_bfv_i]}"
  if [[ -z "$_bfv_fence" ]]; then
    [[ "$_bfv_l" =~ $_bfv_re_fence ]] || continue
    [[ "${BASH_REMATCH[1]:0:1}" == '`' && "${BASH_REMATCH[2]}" == *'`'* ]] && continue
    _bfv_fence="${BASH_REMATCH[1]}"
  elif [[ "$_bfv_l" =~ $_bfv_re_fence && "${BASH_REMATCH[1]:0:1}" == "${_bfv_fence:0:1}" &&
    ${#BASH_REMATCH[1]} -ge ${#_bfv_fence} && "${BASH_REMATCH[2]}" =~ ^[[:space:]]*$ ]]; then
    _bfv_fence=""
  fi
  _BFV_LINES[_bfv_i]=""
done

_bfv_trim_to() {
  local -n __bfv_t="$1"
  __bfv_t="${2#"${2%%[![:space:]]*}"}"
  __bfv_t="${__bfv_t%"${__bfv_t##*[![:space:]]}"}"
}

_BFV_PROBLEMS=()

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

for _bfv_h in ${_BFV_SECTIONS[@]+"${_BFV_SECTIONS[@]}"}; do
  _bfv_start=-1
  for _bfv_i in "${!_BFV_LINES[@]}"; do
    _bfv_trim_to _bfv_t "${_BFV_LINES[_bfv_i]}"
    _bfv_t="${_bfv_t%"${_bfv_t##*[!#[:space:]]}"}"
    if [[ "$_bfv_t" == "##"* ]]; then
      _bfv_tl="${_bfv_t,,}"
      _bfv_tl="${_bfv_tl#\#\#}"
      _bfv_trim_to _bfv_tl "$_bfv_tl"
      if [[ "${_bfv_t:2:1}" == [[:space:]] && "$_bfv_tl" == "${_bfv_h,,}" ]]; then
        _bfv_start=$((_bfv_i + 1))
        break
      fi
    fi
  done
  if ((_bfv_start < 0)); then
    _BFV_PROBLEMS+=("Missing a \"## $_bfv_h\" section: add the heading \"## $_bfv_h\" with its content under it.")
    continue
  fi
  _bfv_has=0
  for ((_bfv_i = _bfv_start; _bfv_i < ${#_BFV_LINES[@]}; _bfv_i++)); do
    _bfv_trim_to _bfv_t "${_BFV_LINES[_bfv_i]}"
    [[ "$_bfv_t" =~ ^#{1,2}[[:space:]] ]] && break
    [[ -n "$_bfv_t" ]] && {
      _bfv_has=1
      break
    }
  done
  ((_bfv_has)) || _BFV_PROBLEMS+=("The \"## $_bfv_h\" section is empty: write its content under the heading.")
done

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
