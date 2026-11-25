#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_GITHUB_POST_CONTENT_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary block-github-post-content PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it
_bgpc_lib="${CLAUDE_PLUGIN_ROOT:-$_HOOK_SELF/..}/lib"
# shellcheck source=../lib/github-post/github-post-body.sh
source "$_bgpc_lib/github-post/github-post-body.sh" || exit 70
# shellcheck source=../lib/secret-detection/secret-patterns.sh
source "$_bgpc_lib/secret-detection/secret-patterns.sh" || exit 70
# shellcheck source=../lib/path-detection/hardcoded-path-patterns.sh
source "$_bgpc_lib/path-detection/hardcoded-path-patterns.sh" || exit 70

start=${EPOCHREALTIME:-}
_bgpc_secrets=0
_bgpc_paths=0
[[ "${CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED:-true}" == true ]] && _bgpc_secrets=1
[[ "${CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED:-true}" == true ]] && _bgpc_paths=1
((_bgpc_secrets || _bgpc_paths)) || exit 0

hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
hook::require_jq_blocking "guardrails-block-github-post-content" "block_github_post_content_enabled"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || jq_rc=$?
guard::payload_verdict "$jq_rc" || exit $(($? == 3 ? 0 : 2))
COMMAND="${HOOK_JQ_FIELDS[0]}"
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
_BGPC_CWD="${HOOK_JQ_FIELDS[2]:-$PWD}"
[[ -n "$COMMAND" ]] || exit 0

_bgpc_re_cli='(^|[^a-z0-9_.-])(gh|curl)(\.exe)?([^a-z0-9_-]|$)'
[[ "${COMMAND,,}" =~ $_bgpc_re_cli ]] || exit 0

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  hook::json_str_object_to data tool "$TOOL_NAME" form "$2" check "$3"
  hook::emit_telemetry "block-github-post-content" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

block_secret() {
  printf '%s\n' \
    "BLOCKED: this command would post a secret/credential pattern to GitHub ($1): $2." \
    "GitHub bodies are public and cannot be unposted cleanly. Remove the value from the body; never paste a token into a comment, PR or API call." >&2
  emit_tel blocked "$1" secret
  exit 2
}

MAX_COMMAND_LEN=16384
if ((${#COMMAND} > MAX_COMMAND_LEN)); then
  ((_bgpc_secrets)) && secrets::any_match "$COMMAND" && block_secret "too-long" "a secret pattern"
  exit 0
fi

ghpost::collect "$COMMAND" "$_BGPC_CWD" "$TOOL_NAME"
if [[ -z "$GHPOST_POST" ]]; then
  emit_tel ok "" ""
  exit 0
fi
ghpost::bodies
ghpost::heredocs

if ((_bgpc_secrets)); then
  _bgpc_labels=""
  _bgpc_hit=0
  for _bgpc_t in ${GHPOST_BODY[@]+"${GHPOST_BODY[@]}"} ${GHPOST_HEREDOCS[@]+"${GHPOST_HEREDOCS[@]}"}; do
    secrets::any_match "$_bgpc_t" || continue
    _bgpc_hit=1
    while IFS= read -r _bgpc_l; do
      _bgpc_l="${_bgpc_l%% (line *}"
      [[ -n "$_bgpc_l" && ", $_bgpc_labels, " != *", $_bgpc_l, "* ]] && _bgpc_labels+="${_bgpc_labels:+, }$_bgpc_l"
    done < <(secrets::scan_text "$_bgpc_t")
  done
  ((_bgpc_hit)) && block_secret "$GHPOST_POST" "${_bgpc_labels:-a secret pattern}"
fi

if ((_bgpc_paths)); then
  hpp::resolve_scan_root "${CLAUDE_PROJECT_DIR:-}"
  _bgpc_viol=""
  _bgpc_texts=()
  for _bgpc_i in "${!GHPOST_BODY[@]}"; do
    _bgpc_t="${GHPOST_BODY[_bgpc_i]}"
    case "${GHPOST_BODY_KIND[_bgpc_i]}" in
    command) continue ;;
    word)
      for _bgpc_f in ${GHPOST_FILES[@]+"${GHPOST_FILES[@]}"}; do
        case "$_bgpc_t" in
        "$_bgpc_f" | "-"*"=$_bgpc_f" | "@$_bgpc_f" | "-"?"$_bgpc_f" | "-"?"@$_bgpc_f" | \
          [!=[:space:]]*"=@$_bgpc_f" | [!=[:space:]]*"=@$_bgpc_f;"* | \
          [!=[:space:]]*"=<$_bgpc_f" | [!=[:space:]]*"=<$_bgpc_f;"* | [!@[:space:]]*"@$_bgpc_f" | \
          "\$(cat $_bgpc_f)" | "\$(<$_bgpc_f)" | "\$(< $_bgpc_f)" | "\`cat $_bgpc_f\`")
          _bgpc_t=""
          break
          ;;
        *) ;;
        esac
      done
      ;;
    attach)
      _bgpc_b="${_bgpc_t##*/}"
      if [[ "$_bgpc_t" == *'#'* ]]; then
        if [[ "${_bgpc_t#*#}" == *[/\\]* ]]; then
          _bgpc_t+=$'\n'"${_bgpc_t#*#}"
        else
          _bgpc_t="${_bgpc_t#*#}"$'\n'"$_bgpc_b"
        fi
      else
        _bgpc_t="$_bgpc_b"
      fi
      ;;
    *) ;;
    esac
    _bgpc_texts+=("$_bgpc_t")
  done
  for _bgpc_t in ${_bgpc_texts[@]+"${_bgpc_texts[@]}"} ${GHPOST_HEREDOCS[@]+"${GHPOST_HEREDOCS[@]}"}; do
    _bgpc_t="${_bgpc_t//\/home\/runner\//<runner>/}"
    _bgpc_t="${_bgpc_t//\/Users\/runner\//<runner>/}"
    _bgpc_t="${_bgpc_t//Users\\runneradmin\\/<runner>\\}"
    _bgpc_t="${_bgpc_t//Users\/runneradmin\//<runner>/}"
    hpp::prefilter "$_bgpc_t" "$SCAN_ROOT"
    [[ "$HPP_GATE" == clean ]] && continue
    _bgpc_out=$(
      hpp::scan_text "$_bgpc_t" "$SCAN_ROOT" ""
      printf x
    )
    _bgpc_out="${_bgpc_out%x}"
    while [[ -n "$_bgpc_out" ]]; do
      _bgpc_b="${_bgpc_out%%$'\n\n'*}"
      if [[ "$_bgpc_b" == "$_bgpc_out" ]]; then _bgpc_out=""; else _bgpc_out="${_bgpc_out#*$'\n\n'}"; fi
      case "$_bgpc_b" in
      "Windows repo path detected:"* | "Escaped Windows repo path detected:"*) ;;
      *) _bgpc_viol+="$_bgpc_b"$'\n\n' ;;
      esac
    done
  done
  if [[ -n "$_bgpc_viol" ]]; then
    {
      printf 'BLOCKED: this command would post hardcoded machine-specific path(s) to GitHub (%s):\n\n' "$GHPOST_POST"
      while IFS= read -r _bgpc_l || [[ -n "$_bgpc_l" ]]; do
        ((${#_bgpc_l} > 160)) && _bgpc_l="${_bgpc_l:0:157}..."
        printf '%s\n' "$_bgpc_l"
      done < <(printf '%s' "$_bgpc_viol")
      # shellcheck disable=SC2016  # the `$` spellings are literal advice, not expansions
      printf 'Use portable alternatives: ~/, $HOME, a repo-relative path, or <placeholder> notation.\n'
    } >&2
    emit_tel blocked "$GHPOST_POST" path
    exit 2
  fi
fi

emit_tel ok "$GHPOST_POST" ""
exit 0
