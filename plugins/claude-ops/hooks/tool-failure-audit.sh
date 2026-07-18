#!/usr/bin/env bash
# PostToolUseFailure hook: emit a telemetry envelope for Write/Edit/Bash tool
# failures. Complements the success-only PostToolUse write-side hooks.
#
# NON-BLOCKING: exit 0 always. Privacy-safe subject convention:
#   Bash       → "Bash:<first-token>" (e.g. "Bash:git", "Bash:dotnet")
#   Write|Edit → tool_name only (no file_path leak)
#   other      → tool_name only
# Full command strings, error messages, file paths, and stdin are NEVER captured.
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switch: CLAUDE_PLUGIN_OPTION_TOOL_FAILURE_AUDIT_ENABLED=false.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "TOOL_FAILURE_AUDIT"
hook::telemetry_enabled || exit 0

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

TOOL=$(hook::jq_field "$INPUT" '.tool_name') || exit 0
CMD=$(hook::jq_field "$INPUT" '.tool_input.command' || true)
SUBJECT=$(hook::extract_bash_subject "$TOOL" "$CMD")

DATA=$(jq -nc --arg subject "$SUBJECT" --arg tool "$TOOL" '{subject: $subject, tool: $tool}')

hook::emit_telemetry "tool-failure-audit" "PostToolUseFailure" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
