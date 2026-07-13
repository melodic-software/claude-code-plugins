#!/usr/bin/env bash
# ConfigChange hook: emit a telemetry envelope for settings/skills mutations.
# Fires on user_settings|project_settings|local_settings|skills changes;
# policy_settings is excluded upstream (cannot be blocked, low signal).
#
# NON-BLOCKING: exit 0 always. The subject is the source identifier
# (path-only, privacy-safe).
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switch: HOOK_CONFIG_CHANGE_AUDIT_ENABLED=false.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "CONFIG_CHANGE_AUDIT"
hook::telemetry_enabled || exit 0

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

CONFIG_SOURCE=$(hook::jq_field "$INPUT" '.source') || exit 0

DATA=$(jq -nc --arg subject "$CONFIG_SOURCE" '{subject: $subject}')

hook::emit_telemetry "config-change-audit" "ConfigChange" "ok" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
