#!/usr/bin/env bash
# PermissionDenied hook: emit a telemetry envelope when the auto-mode classifier
# blocks a tool call (distinct from PermissionRequest, which fires on all
# permission dialogs). Gives a consumer cross-session aggregation of denials.
#
# NON-BLOCKING: exit 0 always; never returns retry:true — denials warrant human
# review, which is the whole point of the classifier blocking the action.
# Privacy-safe subject convention:
#   Bash       → "Bash:<first-token>" (e.g. "Bash:git", "Bash:gh")
#   Write|Edit → tool_name only (no file_path leak)
#   other      → tool_name only
# Full command strings, file paths, and tool_input bodies are NEVER captured.
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switch: CLAUDE_PLUGIN_OPTION_PERMISSION_DENIED_AUDIT_ENABLED=false.

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
hook::check_enabled "PERMISSION_DENIED_AUDIT"
hook::telemetry_enabled || exit 0

START=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0

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

hook::emit_telemetry "permission-denied-audit" "PermissionDenied" "blocked" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
