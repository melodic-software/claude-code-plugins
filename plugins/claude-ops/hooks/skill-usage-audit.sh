#!/usr/bin/env bash
# PostToolUse/Skill hook: record Skill tool invocations for the "measuring
# skills" pattern. Two independent outputs:
#   1. A bespoke second store, skill-usage.jsonl (SkillUse events), written
#      UNCONDITIONALLY. Destination is scope-selected by the skill_usage_scope
#      userConfig (repo — default, project-relative skill_usage_dir under the
#      repo root, git-status-clean via a machine-local .git/info/exclude entry;
#      user — the same subpath under $HOME; data-dir —
#      ${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>). skill_usage_dir defaults
#      to .claude/observability (options arrive as CLAUDE_PLUGIN_OPTION_*).
#   2. A telemetry envelope, emitted only when a consumer wires
#      HOOK_TELEMETRY_SINK (the shared, generic seam).
#
# NON-BLOCKING: exit 0 always. Captures the skill name only — no argument body.
# Kill switch: CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED=false.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
# shellcheck source=claude-ops-paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/claude-ops-paths.sh"

hook::check_enabled "SKILL_USAGE_AUDIT"

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

TOOL=$(hook::jq_field "$INPUT" '.tool_name') || exit 0
[[ "$TOOL" == "Skill" ]] || exit 0

SKILL=$(
  hook::jq_field "$INPUT" '.tool_input.skill' ||
    hook::jq_field "$INPUT" '.tool_input.command' ||
    hook::jq_field "$INPUT" '.tool_input.name'
) || exit 0
SKILL="${SKILL#/}"

# --- Second store: skill-usage.jsonl (unconditional) ------------------------
claude_ops::record_skill_use "PostToolUse" "skill-usage-audit" "$INPUT" "$SKILL" "tool" ""

# --- Telemetry envelope (only when a sink is wired) -------------------------
if hook::telemetry_enabled; then
  DATA=$(jq -nc --arg subject "Skill:$SKILL" --arg skill "$SKILL" \
    '{subject: $subject, skill: $skill, source: "tool"}')
  hook::emit_telemetry "skill-usage-audit" "PostToolUse" "ok" \
    "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"
fi

exit 0
