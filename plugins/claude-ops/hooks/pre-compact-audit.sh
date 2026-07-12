#!/usr/bin/env bash
# PreCompact hook: emit a telemetry envelope for a compaction trigger
# (manual|auto). Useful for diagnosing autocompact-loop regressions and
# validating a CLAUDE_CODE_AUTO_COMPACT_WINDOW threshold.
#
# NON-BLOCKING by policy: exit 0 always; never returns decision:"block".
# The subject is the trigger value.
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switch: HOOK_PRE_COMPACT_AUDIT_ENABLED=false.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "PRE_COMPACT_AUDIT"
hook::telemetry_enabled || exit 0

START=$EPOCHREALTIME

INPUT=$(hook::buffer_stdin) || exit 0

TRIGGER=$(hook::jq_field "$INPUT" '.trigger') || exit 0

DATA=$(jq -nc --arg subject "$TRIGGER" '{subject: $subject}')

hook::emit_telemetry "pre-compact-audit" "PreCompact" "ok" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
