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

# Both payload fields in ONE jq process (hook::jq_fields), not two. A jq spawn is
# ~140 ms of fork() emulation on Windows Git Bash. Failure semantics are
# unchanged: a missing jq or an unparsable payload yields rc 1 here, which exits 0
# exactly as the absent-tool_name skip did, and an absent `.tool_input.command`
# still arrives as the empty string the subject helper already tolerates.
hook::jq_fields "$INPUT" '.tool_name' '.tool_input.command' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
[[ -n "$TOOL" ]] || exit 0
CMD="${HOOK_JQ_FIELDS[1]}"
SUBJECT=$(hook::extract_bash_subject "$TOOL" "$CMD")

DATA=$(jq -nc --arg subject "$SUBJECT" --arg tool "$TOOL" '{subject: $subject, tool: $tool}')

hook::emit_telemetry "tool-failure-audit" "PostToolUseFailure" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
