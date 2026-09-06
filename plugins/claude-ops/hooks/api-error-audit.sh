#!/usr/bin/env bash
# StopFailure hook: emit a telemetry envelope for API-level turn failures
# (rate_limit, billing_error, server_error, ...). Feeds a consumer's
# rate-limit velocity tracking (e.g. the observability skill).
#
# ADVISORY: StopFailure output and exit code are ignored — always exit 0.
# The subject is the StopFailure `error` type only: `error_details` may carry
# prompt fragments or session metadata, so it is never captured (privacy-safe).
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switch: CLAUDE_PLUGIN_OPTION_API_ERROR_AUDIT_ENABLED=false.

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
hook::check_enabled "API_ERROR_AUDIT"
hook::telemetry_enabled || exit 0

START=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0

# data.session_id (additive, hook-telemetry rule 1): the sink routes an
# envelope carrying one into the per-session log beside session-event-log.sh.
# A bash match over the buffered payload, no extra process; empty when the
# payload carries none, and the key is then left out of data.
SESSION_ID=""
[[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]+)\" ]] && SESSION_ID="${BASH_REMATCH[1]}"

ERROR_TYPE=$(hook::jq_field "$INPUT" '.error') || exit 0

DATA=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "$ERROR_TYPE" '{subject: $subject} + (if $session_id == "" then {} else {session_id: $session_id} end)')

hook::emit_telemetry "api-error-audit" "StopFailure" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
