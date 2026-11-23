#!/usr/bin/env bash

set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
guard::abort_boundary hardcoded-path-check PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_HOOK_SELF/.." && pwd)}"
# shellcheck source=../lib/path-detection/hardcoded-path-patterns.sh
source "$PLUGIN_ROOT/lib/path-detection/hardcoded-path-patterns.sh"

start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; buffer
# once, parse each field from it. rc 1 (empty stdin) skips like the empty-field
# guards below; rc 2 (text that is not JSON) FAILS CLOSED — the guard cannot
# evaluate the tool call, and a silent skip would pass exactly the traffic this
# guard exists to stop; rc 3 (a JSON payload cut short by the pipe, a transport
# fault) is a loud skip the dispatcher takes once. buffer_stdin already
# printed the reason to stderr. Buffering does not require jq (hook::buffer_stdin's
# own JSON-completeness check is jq-optional), so it runs before the jq gate
# below — hook::require jq needs the buffered input for its once per session
# and agent notice scoping.
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload. hook::require jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session and agent — see docs/contracts/hook-observability/.
hook::require jq "PreToolUse" guardrails "$INPUT"

# Every payload field this hook can need, in ONE jq process (hook::jq_fields),
# not three — a jq spawn is fork() emulation on Windows Git Bash and this guard
# runs on every Write/Edit/NotebookEdit. All three per-tool content fields are
# fetched together because selecting between them would cost a second process;
# jq reads the same envelope either way, and the tool-specific choice happens
# below in the shell. Failure semantics are unchanged: a missing jq or an
# unparsable payload yields rc 1 here, which exits 0 exactly as the empty-TOOL
# case did — hook::require jq above has already made the degraded state visible
# once per session and agent. NotebookEdit's target is `notebook_path`, appended
# last so the indices the MCP lane reads do not move.
hook::jq_fields "$INPUT" \
  '.tool_name' '.tool_input.file_path' \
  '.tool_input.content' '.tool_input.new_string' '.tool_input.new_source' \
  '.tool_input.path' '.tool_input.notebook_path' || exit 0

hpc_block_nul() {
  guard::refuse_nul
  exit 2
}

hpc_print_alternatives() {
  # shellcheck disable=SC2016  # the `$` spellings are literal advice, not expansions
  printf 'Use portable alternatives: ~/, $HOME, $(pwd), $TMPDIR, '
  printf 'git rev-parse --show-toplevel, or <placeholder> notation.\n'
}

hpc_print_violations() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    ((${#line} > 160)) && line="${line:0:157}..."
    printf '%s\n' "$line"
  done < <(printf '%s' "$1")
}

hpc_labels_json_to() {
  local __hpc_labels
  __hpc_labels=$(grep -E 'detected:$' < <(printf '%s' "$2") 2>/dev/null | sed 's/:$//' | jq -Rn '[inputs]' 2>/dev/null) || __hpc_labels='[]'
  printf -v "$1" '%s' "$__hpc_labels"
}

hpc_send_tel() {
  local labels_json='[]' data
  [[ -z "$3" ]] || hpc_labels_json_to labels_json "$3"
  data=$(jq -n --arg file "$2" --argjson violations "$labels_json" \
    '{tool:"'"$TOOL"'",file:$file,violations:$violations}' 2>/dev/null) ||
    data='{"tool":"","file":"","violations":[]}'
  hook::emit_telemetry "hardcoded-path-check" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

if ((HOOK_JQ_FIELDS_NUL)); then
  hpc_block_nul
fi

TOOL="${HOOK_JQ_FIELDS[0]}"

hpc_path_allowlisted() {
  case "$1" in
  *.claude/hooks/* | *.lefthook/*) return 0 ;;
  *.claude/projects/*) return 0 ;;
  *) return 1 ;;
  esac
}

hpc_mcp_lane() {
  local count=1 i path content violations="" first_offender="" scan_out
  local single_path="${HOOK_JQ_FIELDS[5]}" single_content="${HOOK_JQ_FIELDS[2]}"

  hpp::resolve_scan_root "${CLAUDE_PROJECT_DIR:-}"

  if [[ "$TOOL" == *__push_files ]]; then
    hook::jq_fields "$INPUT" '.tool_input.files | length' || return 0
    count="${HOOK_JQ_FIELDS[0]}"
    [[ "$count" =~ ^[0-9]+$ ]] || return 0
  fi

  for ((i = 0; i < count; i++)); do
    if [[ "$TOOL" == *__push_files ]]; then
      hook::jq_fields "$INPUT" ".tool_input.files[$i].path" ".tool_input.files[$i].content" || continue
      path="${HOOK_JQ_FIELDS[0]}"
      content="${HOOK_JQ_FIELDS[1]}"
    else
      path="$single_path"
      content="$single_content"
    fi

    if ((HOOK_JQ_FIELDS_NUL)); then
      hpc_block_nul
    fi

    [[ -n "$path" && -n "$content" ]] || continue
    hpc_path_allowlisted "${path//\\//}" && continue

    scan_out=$(
      hpp::scan_text "$content" "$SCAN_ROOT" "$path"
      printf x
    )
    scan_out=${scan_out%x}
    [[ -n "$scan_out" ]] || continue
    [[ -n "$first_offender" ]] || first_offender="$path"
    violations+="$path:"$'\n'"$scan_out"
  done

  [[ -n "$violations" ]] || return 0

  {
    printf 'Hardcoded machine-specific path(s) in content bound for GitHub:\n\n'
    hpc_print_violations "$violations"
    hpc_print_alternatives
  } >&2

  if [[ -n "$start" ]] && hook::telemetry_enabled; then
    hpc_send_tel blocked "$first_offender" "$violations"
  fi
  exit 2
}

case "$TOOL" in
Write | Edit | NotebookEdit) IS_MCP=0 ;;
mcp__github__push_files | mcp__github__create_or_update_file | \
  mcp__plugin_*_github__push_files | mcp__plugin_*_github__create_or_update_file) IS_MCP=1 ;;
*) exit 0 ;;
esac

if ((IS_MCP)); then
  hpc_mcp_lane
  exit 0
fi

FILE="${HOOK_JQ_FIELDS[1]}"
[[ "$TOOL" == NotebookEdit && -n "${HOOK_JQ_FIELDS[6]}" ]] && FILE="${HOOK_JQ_FIELDS[6]}"
[[ -n "$FILE" ]] || exit 0

NORM_FILE="${FILE//\\//}"

[[ -n "${CLAUDE_PROJECT_DIR:-}" ]] || exit 0

case "$TOOL" in
Write) CONTENT="${HOOK_JQ_FIELDS[2]}" ;;
Edit) CONTENT="${HOOK_JQ_FIELDS[3]}" ;;
NotebookEdit) CONTENT="${HOOK_JQ_FIELDS[4]}" ;;
*) exit 0 ;;
esac

if [[ -z "$start" ]] || ! hook::telemetry_enabled; then
  hpp::prefilter "$CONTENT" "$CLAUDE_PROJECT_DIR"
  [[ "$HPP_GATE" == clean ]] && exit 0
fi
{ _hpc_git="$(hook::git_untrusted -C "$CLAUDE_PROJECT_DIR" rev-parse --is-inside-work-tree --show-toplevel)"; } 2>/dev/null
[[ "${_hpc_git%%$'\n'*}" == "true" ]] || exit 0
_hpc_toplevel=""
[[ "$_hpc_git" == *$'\n'* ]] && _hpc_toplevel=${_hpc_git#*$'\n'}
_scope_file=""
hook::normalize_path_to _scope_file "$FILE"
_scope_project=""
hook::normalize_path_to _scope_project "${CLAUDE_PROJECT_DIR}"
_scope_project="${_scope_project%/}"
case "$_scope_file" in
"$_scope_project"/*) ;;
*) exit 0 ;;
esac

hpc_path_allowlisted "$NORM_FILE" && exit 0

if hook::git_untrusted -C "$CLAUDE_PROJECT_DIR" check-ignore -q "$FILE" 2>/dev/null; then
  exit 0
fi

[[ -n "${CONTENT:-}" ]] || exit 0

PROJECT_ROOT=$CLAUDE_PROJECT_DIR

hpp::resolve_scan_root "$PROJECT_ROOT" "$_hpc_toplevel"

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local file_rel=""
  hook::repo_relative_path_to file_rel "$FILE" "${PROJECT_ROOT%/}"
  hpc_send_tel "$1" "$file_rel" "$2"
}

VIOLATIONS=""
hpp::prefilter "$CONTENT" "$SCAN_ROOT"
if [[ "$HPP_GATE" != clean ]]; then
  VIOLATIONS=$(
    hpp::scan_text "$CONTENT" "$SCAN_ROOT" "$FILE"
    printf x
  )
  VIOLATIONS=${VIOLATIONS%x}
fi
if [[ -n "$VIOLATIONS" ]]; then
  show_file="$FILE"
  [[ "$FILE" == "${PROJECT_ROOT%/}/"?* ]] && show_file="${FILE#"${PROJECT_ROOT%/}/"}"
  {
    printf 'Hardcoded machine-specific path(s) in %s:\n\n' "$show_file"
    hpc_print_violations "$VIOLATIONS"
    hpc_print_alternatives
  } >&2
  emit_tel "blocked" "$VIOLATIONS"
  exit 2
fi

emit_tel "ok" ""
exit 0
