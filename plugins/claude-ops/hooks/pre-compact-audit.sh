#!/usr/bin/env bash
# PreCompact hook: emit a telemetry envelope for a compaction trigger
# (manual|auto). Useful for diagnosing autocompact-loop regressions and
# validating a CLAUDE_CODE_AUTO_COMPACT_WINDOW threshold.
#
# NON-BLOCKING by policy: exit 0 always; never returns decision:"block".
# The subject is the trigger value.
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switch: CLAUDE_PLUGIN_OPTION_PRE_COMPACT_AUDIT_ENABLED=false.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "PRE_COMPACT_AUDIT"
hook::telemetry_enabled || exit 0

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

# data.session_id (additive, hook-telemetry rule 1): the sink routes an
# envelope carrying one into the per-session log beside session-event-log.sh.
# A bash match over the buffered payload, no extra process; empty when the
# payload carries none, and the key is then left out of data.
SESSION_ID=""
[[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([A-Za-z0-9._-]+)\" ]] && SESSION_ID="${BASH_REMATCH[1]}"

TRIGGER=$(hook::jq_field "$INPUT" '.trigger') || exit 0

DATA=$(jq -nc --arg session_id "$SESSION_ID" --arg subject "$TRIGGER" '{subject: $subject} + (if $session_id == "" then {} else {session_id: $session_id} end)')

hook::emit_telemetry "pre-compact-audit" "PreCompact" "ok" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
