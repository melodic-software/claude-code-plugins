#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED:-true}" == "false" ]] && exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-fix-request-post PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it
# shellcheck source=../lib/github-post/github-post-body.sh
source "${CLAUDE_PLUGIN_ROOT:-$_HOOK_SELF/..}/lib/github-post/github-post-body.sh" || exit 70

_bfr_enabled="${CLAUDE_PLUGIN_OPTION_BLOCK_FIX_REQUEST_POST_ENABLED:-true}"
start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
[[ "$_bfr_enabled" == true ]] ||
  guard::bad_switch_notice block_fix_request_post_enabled "$_bfr_enabled" "$INPUT"

hook::require_jq_blocking "guardrails-block-fix-request-post" "block_fix_request_post_enabled"

_bfr_settle_fields() {
  if (($1 == 2)); then
    guard::refuse_unparsable
    exit 2
  fi
  (($1 == 0)) || exit 0
  if ((HOOK_JQ_FIELDS_NUL)); then
    guard::refuse_nul
    exit 2
  fi
}

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || jq_rc=$?
_bfr_settle_fields "$jq_rc"
COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
_BFR_CWD="${HOOK_JQ_FIELDS[2]:-$PWD}"

_BFR_PHRASE='pr-fix lane: please fix this finding'
_bfr_q="[\"'=]"
_BFR_RE_ANY="(["$'\n'"\"'=])${_BFR_PHRASE}([^[:alnum:]_]|\$)"
_BFR_RE_LINE="^(.*${_bfr_q})?${_BFR_PHRASE}([^[:alnum:]_]|\$)"
_BFR_RE_FENCE="^ {0,3}(\`\`\`|~~~)"

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" form "$2"
  hook::emit_telemetry "block-fix-request-post" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

_BFR_TEAM_REL="docs/conventions/guardrails.yaml"
_bfr_allowed() {
  local root text recs val key=$'\nfix_request_post\t'
  hook::repo_root_to root "$_BFR_CWD" || return 1
  text=$(hook::git_untrusted -C "$root" show "refs/remotes/origin/HEAD:$_BFR_TEAM_REL" 2>/dev/null) || return 1
  if ! recs=$(LC_ALL=C awk -v STRICT=1 -f "$_HOOK_SELF/yaml-subset.awk" <<<"$text" 2>/dev/null); then
    printf 'guardrails: %s does not parse; fix_request_post stays block.\n' "$_BFR_TEAM_REL" >&2
    return 1
  fi
  recs=$'\n'"$recs"
  [[ "$recs" == *"$key"* ]] || return 1
  val="${recs#*"$key"}"
  val="${val%%$'\n'*}"
  [[ "$val" == allow ]] && return 0
  [[ "$val" == block ]] ||
    printf "guardrails: %s sets fix_request_post: '%s', not allow or block; it stays block.\n" "$_BFR_TEAM_REL" "$val" >&2
  return 1
}

block() {
  if _bfr_allowed; then
    emit_tel ok "$1, allowed by fix_request_post"
    exit 0
  fi
  printf '%s\n' \
    "BLOCKED: this would post the PR-fix lane fix request (a line starting \"PR-fix lane: please fix this finding\") to GitHub ($1)." \
    "Only the repository owner may post a fix request, typed in the GitHub UI: the address-feedback lane acts on it with push credentials, and an agent posts with the owner's token (owner decision, https://github.com/melodic-software/claude-code-plugins/issues/8438)." \
    "Leave the request to the owner. To cite the phrase, put it after \"> \" or inside a code fence." >&2
  emit_tel blocked "$1"
  exit 2
}

_bfr_lines() {
  [[ "$1" == *"$_BFR_PHRASE"* ]] || return 1
  if [[ "$1" != *'```'* && "$1" != *'~~~'* ]]; then
    [[ $'\n'"$1" =~ $_BFR_RE_ANY ]]
    return
  fi
  local line fenced=0
  local -a lines=()
  mapfile -t lines <<<"$1"
  for line in "${lines[@]}"; do
    if [[ "$line" =~ $_BFR_RE_FENCE ]]; then
      fenced=$((1 - fenced))
    elif ((! fenced)) && [[ "$line" =~ $_BFR_RE_LINE ]]; then
      return 0
    fi
  done
  return 1
}

# shellcheck disable=SC1003  # '\' compares a literal backslash, not a quote escape
_bfr_carries() {
  local t="${1,,}" d
  t="${t//$'\r'/}"
  _bfr_lines "$t" && return 0
  if [[ "$t" == *'\'* ]]; then
    d="${t//\\r/}"
    d="${d//\\n/$'\n'}"
    d="${d//\\u000a/$'\n'}"
    d="${d//\\u000d/}"
    d="${d//\\u0020/ }"
    d="${d//\\u002d/-}"
    d="${d//\\u003a/:}"
    d="${d//\\t/$'\t'}"
    d="${d//\\\"/\"}"
    d="${d//\\\'/\'}"
    d="${d//\\ / }"
    _bfr_lines "$d" && return 0
  fi
  if [[ "$t" == *%* || "$t" == *+* ]]; then
    d="${t//%0d/}"
    d="${d//%0a/$'\n'}"
    d="${d//+/ }"
    d="${d//%20/ }"
    d="${d//%2d/-}"
    d="${d//%3a/:}"
    d="${d//%22/\"}"
    d="${d//%27/\'}"
    d="${d//%3d/=}"
    _bfr_lines "$d" && return 0
  fi
  return 1
}

if [[ "$TOOL_NAME" == mcp__* ]]; then
  jq_rc=0
  hook::jq_fields "$INPUT" '.tool_input.body' '.tool_input.comments' || jq_rc=$?
  _bfr_settle_fields "$jq_rc"
  for _bfr_t in "${HOOK_JQ_FIELDS[@]}"; do
    _bfr_carries "$_bfr_t" && block "${TOOL_NAME##*__}"
  done
  emit_tel ok ""
  exit 0
fi

[[ -n "$COMMAND" ]] || exit 0
_bfr_lc="${COMMAND,,}"
MAX_COMMAND_LEN=16384
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  [[ "$_bfr_lc" == *"$_BFR_PHRASE"* ]] && block "too-long"
  exit 0
fi
_bfr_flat="${_bfr_lc//[\\\'\"]/}"
if [[ "$_bfr_flat" != *"pr-fix lane"* && "$_bfr_flat" != *pr-fix%20lane* && "$_bfr_flat" != *pr-fix+lane* ]]; then
  _bfr_re_cli='(^|[^a-z0-9_.-])(gh|curl)(\.exe)?([^a-z0-9_-]|$)'
  [[ "$_bfr_lc" =~ $_bfr_re_cli ]] || exit 0
  [[ "$_bfr_lc" == *@* || "$_bfr_lc" == *-f* || "$_bfr_lc" == *--input* || "$_bfr_lc" == *'<'* || "$_bfr_lc" == *cat* ]] || exit 0
fi

ghpost::collect "$COMMAND" "$_BFR_CWD" "$TOOL_NAME"
if [[ -z "$GHPOST_POST" ]]; then
  emit_tel ok ""
  exit 0
fi

ghpost::bodies
for _bfr_i in "${!GHPOST_BODY[@]}"; do
  _bfr_carries "${GHPOST_BODY[_bfr_i]}" &&
    block "$GHPOST_POST${GHPOST_BODY_SRC[_bfr_i]:+, from ${GHPOST_BODY_SRC[_bfr_i]}}"
done
emit_tel ok ""
exit 0
