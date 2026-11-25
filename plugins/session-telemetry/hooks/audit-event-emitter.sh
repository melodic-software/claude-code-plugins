#!/usr/bin/env bash
set -uo pipefail

_any_on=0
for _opt in API_ERROR_AUDIT CONFIG_CHANGE_AUDIT INSTRUCTIONS_LOADED_AUDIT \
  PERMISSION_DENIED_AUDIT PRE_COMPACT_AUDIT SKILL_USAGE_AUDIT TOOL_FAILURE_AUDIT; do
  _var="CLAUDE_PLUGIN_OPTION_${_opt}_ENABLED"
  if [[ "${!_var:-true}" == "true" ]]; then
    _any_on=1
    break
  fi
done
((_any_on)) || exit 0

# Parameter expansion, not $(dirname): Bash runs every command substitution in a subshell:
# https://www.gnu.org/software/bash/manual/html_node/Command-Substitution.html
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

START=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0

EVENT=""
[[ "$INPUT" =~ \"hook_event_name\"[[:space:]]*:[[:space:]]*\"([A-Za-z]+)\" ]] && EVENT="${BASH_REMATCH[1]}"

SESSION_ID=""
[[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]+)\" ]] && SESSION_ID="${BASH_REMATCH[1]}"

emit::subject() {
  local data
  data=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "$1" \
    '{subject: $subject} + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "$2" "$3" "$4" "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

emit::subject_row() {
  local subject
  subject=$(hook::jq_field "$INPUT" "$1") || return 0
  emit::subject "$subject" "$2" "$3" "$4"
}

emit::tool_row() {
  local tool cmd subject data
  hook::jq_fields "$INPUT" '.tool_name' '.tool_input.command' || return 0
  tool="${HOOK_JQ_FIELDS[0]}"
  [[ -n "$tool" ]] || return 0
  cmd="${HOOK_JQ_FIELDS[1]}"
  subject=$(hook::extract_bash_subject "$tool" "$cmd")
  data=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "$subject" --arg tool "$tool" \
    '{subject: $subject, tool: $tool} + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "$1" "$2" "$3" "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

emit::instructions_loaded_row() {
  local file_path load_reason file_disp project_dir
  hook::jq_fields "$INPUT" '.file_path' '.load_reason' || return 0
  file_path="${HOOK_JQ_FIELDS[0]}"
  load_reason="${HOOK_JQ_FIELDS[1]}"

  [[ -n "$file_path$load_reason" ]] || return 0

  if [[ "$load_reason" == "session_start" &&
    "${CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START:-false}" != "true" ]]; then
    return 0
  fi

  file_disp=""
  if [[ -n "$file_path" ]]; then
    project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
    case "$file_path" in
    "$project_dir"/*) file_disp="${file_path#"$project_dir"/}" ;;
    *) file_disp="${file_path##*/}" ;;
    esac
  fi

  emit::subject "${file_disp}:${load_reason}" "instructions-loaded-audit" "InstructionsLoaded" "ok"
}

emit::skill_expansion_row() {
  local skill exp_type data
  skill=$(hook::jq_field "$INPUT" '.command_name') || return 0
  skill="${skill#/}"

  exp_type=$(printf '%s' "$INPUT" | jq -r '(.expansion_type // empty) | gsub("\r";"")' 2>/dev/null)

  harness_ops::record_skill_use "UserPromptExpansion" "skill-usage-expansion-audit" \
    "$INPUT" "$skill" "expansion" "$exp_type"

  hook::telemetry_enabled || return 0
  data=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "Skill:$skill" --arg skill "$skill" --arg exp "$exp_type" \
    '{subject: $subject, skill: $skill, source: "expansion"}
     + (if $exp != "" then {expansion_type: $exp} else {} end) + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "skill-usage-audit" "UserPromptExpansion" "ok" \
    "$START" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

case "$EVENT" in
StopFailure)
  hook::is_enabled "API_ERROR_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::subject_row '.error' "api-error-audit" "StopFailure" "error"
  ;;
ConfigChange)
  hook::is_enabled "CONFIG_CHANGE_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::subject_row '.source' "config-change-audit" "ConfigChange" "ok"
  ;;
PreCompact)
  hook::is_enabled "PRE_COMPACT_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::subject_row '.trigger' "pre-compact-audit" "PreCompact" "ok"
  ;;
PostToolUseFailure)
  hook::is_enabled "TOOL_FAILURE_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::tool_row "tool-failure-audit" "PostToolUseFailure" "error"
  ;;
PermissionDenied)
  hook::is_enabled "PERMISSION_DENIED_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::tool_row "permission-denied-audit" "PermissionDenied" "blocked"
  ;;
InstructionsLoaded)
  hook::is_enabled "INSTRUCTIONS_LOADED_AUDIT" || exit 0
  hook::telemetry_enabled || exit 0
  emit::instructions_loaded_row
  ;;
UserPromptExpansion)
  hook::is_enabled "SKILL_USAGE_AUDIT" || exit 0
  # shellcheck source=harness-ops-paths.sh
  source "$HOOK_DIR/harness-ops-paths.sh"
  emit::skill_expansion_row
  ;;
*)
  ;;
esac

exit 0
