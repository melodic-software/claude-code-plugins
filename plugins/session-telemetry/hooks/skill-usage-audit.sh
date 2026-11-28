#!/usr/bin/env bash
set -uo pipefail

[[ "${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED:-true}" == "true" ]] || exit 0
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=harness-ops-paths.sh
source "$HOOK_DIR/harness-ops-paths.sh"
START=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0

SESSION_ID=""
[[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]+)\" ]] && SESSION_ID="${BASH_REMATCH[1]}"

TOOL=$(hook::jq_field "$INPUT" '.tool_name') || exit 0
[[ "$TOOL" == "Skill" ]] || exit 0

SKILL=$(
  hook::jq_field "$INPUT" '.tool_input.skill' ||
    hook::jq_field "$INPUT" '.tool_input.command' ||
    hook::jq_field "$INPUT" '.tool_input.name'
) || exit 0
SKILL="${SKILL#/}"

harness_ops::record_skill_use "PostToolUse" "skill-usage-audit" "$INPUT" "$SKILL" "tool" ""

if hook::telemetry_enabled; then
  DATA=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "Skill:$SKILL" --arg skill "$SKILL" \
    '{subject: $subject, skill: $skill, source: "tool"} + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "skill-usage-audit" "PostToolUse" "ok" \
    "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"
fi

exit 0
