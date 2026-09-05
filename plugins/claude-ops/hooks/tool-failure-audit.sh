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

# data.session_id (additive, hook-telemetry rule 1): the sink routes an
# envelope carrying one into the per-session log beside session-event-log.sh.
# A bash match over the buffered payload, no extra process; empty when the
# payload carries none, and the key is then left out of data.
SESSION_ID=""
[[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]+)\" ]] && SESSION_ID="${BASH_REMATCH[1]}"

# Both payload fields in ONE jq process (hook::jq_fields), not two: a jq spawn is
# ~140 ms of fork() emulation on Windows Git Bash. A missing jq or an unparsable
# payload returns non-zero here and exits 0, the same silent skip an absent
# tool_name takes below; an absent `.tool_input.command` arrives as the empty
# string the subject helper tolerates.
hook::jq_fields "$INPUT" '.tool_name' '.tool_input.command' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
[[ -n "$TOOL" ]] || exit 0
CMD="${HOOK_JQ_FIELDS[1]}"
SUBJECT=$(hook::extract_bash_subject "$TOOL" "$CMD")

DATA=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "$SUBJECT" --arg tool "$TOOL" '{subject: $subject, tool: $tool} + (if $session_id == "" then {} else {session_id: $session_id} end)')

hook::emit_telemetry "tool-failure-audit" "PostToolUseFailure" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
