#!/usr/bin/env bash
# UserPromptExpansion hook: record user-typed slash-command / MCP-prompt
# invocations for the "measuring skills" pattern. This is the second producer of
# the skill-usage-audit signal — the PostToolUse/Skill hook only fires when the
# MODEL invokes the Skill tool, so a user who types "/skill" directly (a
# UserPromptExpansion, which bypasses the Skill tool call) is missed by that
# path. The two events are disjoint (model-tool-call vs user-typed), so no dedup
# is required; each carries a `source` field (`tool` vs `expansion`) so
# consumers can tell the two paths apart.
#
# Same two outputs as the tool-path producer:
#   1. The bespoke second store, skill-usage.jsonl (SkillUse events), written
#      UNCONDITIONALLY, at the same project-relative destination (the
#      skill_usage_dir userConfig, else .claude/observability).
#   2. The unified skill-usage-audit telemetry envelope, emitted only when a
#      consumer wires HOOK_TELEMETRY_SINK. Keeps the same `hook` id and data
#      schema so the store stays unified across both producers.
#
# Registered with NO matcher, so it fires for every expanded command; emission
# keys on command_name (always present). expansion_type (slash_command vs
# mcp_prompt) is recorded when present so the distinction is preserved
# downstream, but is never gated on — a CC build that omits it must still record
# the user-typed path rather than silently drop it.
#
# NON-BLOCKING: exit 0 always. Captures the command name only — no argument body.
# Kill switch: HOOK_SKILL_USAGE_AUDIT_ENABLED=false (shared with the tool-path
# producer — one switch disables the whole skill-usage-audit feature).

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
# shellcheck source=claude-ops-paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/claude-ops-paths.sh"

hook::check_enabled "SKILL_USAGE_AUDIT"

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

SKILL=$(hook::jq_field "$INPUT" '.command_name') || exit 0
SKILL="${SKILL#/}"

# Optional: slash_command | mcp_prompt. Recorded when present, never gated on.
EXP_TYPE=$(jq -r '(.expansion_type // empty) | gsub("\r";"")' <<<"$INPUT" 2>/dev/null)

# --- Second store: skill-usage.jsonl (unconditional) ------------------------
project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
rel_dir="${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR:-.claude/observability}"
log_dir=""
if ! log_dir=$(claude_ops::resolve_project_relative_dir "$project_dir" "$rel_dir"); then
  hook::emit_additional_context "UserPromptExpansion" \
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
      --arg exp "$EXP_TYPE" \
      '{ts: $ts, event: "SkillUse", skill: $skill, branch: $branch, hook: $hook, source: "expansion"}
       + (if $exp != "" then {expansion_type: $exp} else {} end)'
  ) && hook::append_jsonl "${log_dir}/skill-usage.jsonl" "$line"
else
  hook::emit_additional_context "UserPromptExpansion" \
    "claude-ops skipped skill-usage logging: the configured project-relative destination could not be created safely."
fi

# --- Telemetry envelope (only when a sink is wired) -------------------------
if hook::telemetry_enabled; then
  DATA=$(jq -nc --arg subject "Skill:$SKILL" --arg skill "$SKILL" --arg exp "$EXP_TYPE" \
    '{subject: $subject, skill: $skill, source: "expansion"}
     + (if $exp != "" then {expansion_type: $exp} else {} end)')
  hook::emit_telemetry "skill-usage-audit" "UserPromptExpansion" "ok" \
    "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"
fi

exit 0
