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
project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
rel_dir="${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_DIR:-.claude/observability}"
scope="${CLAUDE_PLUGIN_OPTION_SKILL_USAGE_SCOPE:-repo}"
case "$scope" in
repo | user | data-dir) ;;
*)
  if hook::notice_once "skill-usage-audit-badscope" "$INPUT"; then
    hook::emit_skip_notice "PostToolUse" \
      "claude-ops skill-usage logging: unknown skill_usage_scope \"${scope}\" (valid: repo, user, data-dir) — using the default repo scope."
  fi
  scope="repo"
  ;;
esac
log_dir=""
if ! log_dir=$(claude_ops::resolve_skill_usage_dir "$scope" "$project_dir" "$rel_dir"); then
  if hook::notice_once "skill-usage-audit-badconfig" "$INPUT"; then
    hook::emit_skip_notice "PostToolUse" \
      "claude-ops skipped skill-usage logging: the skill-usage destination is invalid for scope \"${scope}\" (repo/user scopes need a contained relative skill_usage_dir — no absolute, drive, UNC, traversal, or escaping symlink path; data-dir needs CLAUDE_PLUGIN_DATA)."
  fi
elif mkdir -p "$log_dir" 2>/dev/null &&
  verified_log_dir=$(claude_ops::resolve_skill_usage_dir "$scope" "$project_dir" "$rel_dir") &&
  [[ "$verified_log_dir" == "$log_dir" ]]; then
  [[ "$scope" == "repo" ]] && claude_ops::ensure_git_exclude "$project_dir" "$rel_dir"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S)
  branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
  line=$(
    jq -nc \
      --arg ts "$ts" \
      --arg skill "$SKILL" \
      --arg branch "$branch" \
      --arg project "$(basename -- "$project_dir")" \
      --arg hook "skill-usage-audit" \
      '{ts: $ts, event: "SkillUse", skill: $skill, branch: $branch, project: $project, hook: $hook, source: "tool"}'
  ) && hook::append_jsonl "${log_dir}/skill-usage.jsonl" "$line"
else
  if hook::notice_once "skill-usage-audit-nodest" "$INPUT"; then
    hook::emit_skip_notice "PostToolUse" \
      "claude-ops skipped skill-usage logging: the configured destination could not be created safely."
  fi
fi

# --- Telemetry envelope (only when a sink is wired) -------------------------
if hook::telemetry_enabled; then
  DATA=$(jq -nc --arg subject "Skill:$SKILL" --arg skill "$SKILL" \
    '{subject: $subject, skill: $skill, source: "tool"}')
  hook::emit_telemetry "skill-usage-audit" "PostToolUse" "ok" \
    "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"
fi

exit 0
