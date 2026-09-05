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

# Kill switch FIRST, before any library is sourced: a disabled hook must not
# pay to parse hook-utils.sh to learn it is off. Same predicate as
# hook::is_enabled; scripts/check-killswitch-hoist.sh pins the two together.
[[ "${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED:-true}" == "true" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"
# shellcheck source=claude-ops-paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/claude-ops-paths.sh"

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

# data.session_id (additive, hook-telemetry rule 1): the sink routes an
# envelope carrying one into the per-session log beside session-event-log.sh.
# A bash match over the buffered payload, no extra process; empty when the
# payload carries none, and the key is then left out of data.
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

# --- Second store: skill-usage.jsonl (unconditional) ------------------------
claude_ops::record_skill_use "PostToolUse" "skill-usage-audit" "$INPUT" "$SKILL" "tool" ""

# --- Telemetry envelope (only when a sink is wired) -------------------------
if hook::telemetry_enabled; then
  DATA=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "Skill:$SKILL" --arg skill "$SKILL" \
    '{subject: $subject, skill: $skill, source: "tool"} + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "skill-usage-audit" "PostToolUse" "ok" \
    "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"
fi

exit 0
