#!/usr/bin/env bash
# PostToolUse/Skill hook: record Skill tool invocations for the "measuring
# skills" pattern. Two independent outputs:
#   1. A bespoke second store, skill-usage.jsonl (SkillUse events), written
#      UNCONDITIONALLY. Its directory is project-relative and defaults to
#      .claude/observability; override with the skill_usage_dir userConfig
#      (exported to this hook as CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR).
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
  hook::jq_field "$INPUT" '.tool_input.skill' \
    || hook::jq_field "$INPUT" '.tool_input.command' \
    || hook::jq_field "$INPUT" '.tool_input.name'
) || exit 0
SKILL="${SKILL#/}"

# --- Second store: skill-usage.jsonl (unconditional) ------------------------
project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
rel_dir="${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR:-.claude/observability}"
log_dir=""
if ! log_dir=$(claude_ops::resolve_project_relative_dir "$project_dir" "$rel_dir"); then
  hook::emit_additional_context "PostToolUse" \
    "claude-ops skipped skill-usage logging: skill_usage_dir must be a contained project-relative path (no absolute, drive, UNC, traversal, or escaping symlink path)."
elif mkdir -p "$log_dir" 2>/dev/null \
  && verified_log_dir=$(claude_ops::resolve_project_relative_dir "$project_dir" "$rel_dir") \
  && [[ "$verified_log_dir" == "$log_dir" ]]; then
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)
  branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  line=$(
    jq -nc \
      --arg ts "$ts" \
      --arg skill "$SKILL" \
      --arg branch "$branch" \
      --arg hook "skill-usage-audit" \
      '{ts: $ts, event: "SkillUse", skill: $skill, branch: $branch, hook: $hook, source: "tool"}'
  ) && hook::append_jsonl "${log_dir}/skill-usage.jsonl" "$line"
else
  hook::emit_additional_context "PostToolUse" \
    "claude-ops skipped skill-usage logging: the configured project-relative destination could not be created safely."
fi

# --- Telemetry envelope (only when a sink is wired) -------------------------
if hook::telemetry_enabled; then
  DATA=$(jq -nc --arg subject "Skill:$SKILL" --arg skill "$SKILL" \
    '{subject: $subject, skill: $skill, source: "tool"}')
  hook::emit_telemetry "skill-usage-audit" "PostToolUse" "ok" \
    "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"
fi

exit 0
