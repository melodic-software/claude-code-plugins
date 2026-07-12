#!/usr/bin/env bash
# StopFailure hook: emit a telemetry envelope for API-level turn failures
# (rate_limit, billing_error, server_error, ...). Feeds a consumer's
# rate-limit velocity tracking (e.g. the claude-observability skill).
#
# ADVISORY: StopFailure output and exit code are ignored — always exit 0.
# The subject is the StopFailure `error` type only: `error_details` may carry
# prompt fragments or session metadata, so it is never captured (privacy-safe).
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switch: HOOK_API_ERROR_AUDIT_ENABLED=false.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "API_ERROR_AUDIT"
hook::telemetry_enabled || exit 0

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

ERROR_TYPE=$(hook::jq_field "$INPUT" '.error') || exit 0

DATA=$(jq -nc --arg subject "$ERROR_TYPE" '{subject: $subject}')

hook::emit_telemetry "api-error-audit" "StopFailure" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
