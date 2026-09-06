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
#      UNCONDITIONALLY, at the same scope-selected destination as the tool-path
#      producer (skill_usage_scope: repo | user | data-dir; skill_usage_dir,
#      else .claude/observability, for the repo/user scopes).
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
# Kill switch: CLAUDE_PLUGIN_OPTION_SKILL_USAGE_AUDIT_ENABLED=false (shared with the tool-path
# producer — one switch disables the whole skill-usage-audit feature).

set -uo pipefail
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=claude-ops-paths.sh
source "$HOOK_DIR/claude-ops-paths.sh"
hook::check_enabled "SKILL_USAGE_AUDIT"

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

# data.session_id (additive, hook-telemetry rule 1): the sink routes an
# envelope carrying one into the per-session log beside session-event-log.sh.
# A bash match over the buffered payload, no extra process; empty when the
# payload carries none, and the key is then left out of data.
SESSION_ID=""
[[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]+)\" ]] && SESSION_ID="${BASH_REMATCH[1]}"

SKILL=$(hook::jq_field "$INPUT" '.command_name') || exit 0
SKILL="${SKILL#/}"

# Optional: slash_command | mcp_prompt. Recorded when present, never gated on.
# Fed through `printf | jq` rather than a here-string: bash fills a here-string's
# pipe itself, so a payload at or above the pipe capacity blocks before jq runs.
EXP_TYPE=$(printf '%s' "$INPUT" | jq -r '(.expansion_type // empty) | gsub("\r";"")' 2>/dev/null)

# --- Second store: skill-usage.jsonl (unconditional) ------------------------
claude_ops::record_skill_use "UserPromptExpansion" "skill-usage-expansion-audit" \
  "$INPUT" "$SKILL" "expansion" "$EXP_TYPE"

# --- Telemetry envelope (only when a sink is wired) -------------------------
if hook::telemetry_enabled; then
  DATA=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "Skill:$SKILL" --arg skill "$SKILL" --arg exp "$EXP_TYPE" \
    '{subject: $subject, skill: $skill, source: "expansion"}
     + (if $exp != "" then {expansion_type: $exp} else {} end) + (if $session_id == "" then {} else {session_id: $session_id} end)')
  hook::emit_telemetry "skill-usage-audit" "UserPromptExpansion" "ok" \
    "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"
fi

exit 0
