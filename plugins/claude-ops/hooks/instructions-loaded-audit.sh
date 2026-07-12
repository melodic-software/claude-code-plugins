#!/usr/bin/env bash
# InstructionsLoaded hook: emit a telemetry envelope for rule/instruction file
# loads. Lets a consumer validate that `paths:` frontmatter is matching and
# @-includes resolve (which rules actually load).
#
# ADVISORY: InstructionsLoaded exit code is ignored — always exit 0.
# The subject is "<file_path>:<load_reason>" so query analysis can group loads
# by reason without parsing extra fields.
#
# Write-time filter: session_start loads are deterministic (the same always-load
# files fire every boot) and high-volume, so they are dropped by default. Opt
# back in for one-off debugging with:
#   HOOK_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START=true
#
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switches:
#   HOOK_INSTRUCTIONS_LOADED_AUDIT_ENABLED=false           — disable entirely
#   HOOK_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START=true   — opt back into session_start

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "INSTRUCTIONS_LOADED_AUDIT"
hook::telemetry_enabled || exit 0

START=$EPOCHREALTIME

INPUT=$(hook::buffer_stdin) || exit 0

FILE_PATH=$(hook::jq_field "$INPUT" '.file_path' || true)
LOAD_REASON=$(hook::jq_field "$INPUT" '.load_reason' || true)

# Need at least one of the two; a pure missing payload is a silent skip.
[[ -n "$FILE_PATH$LOAD_REASON" ]] || exit 0

# Drop session_start at write time unless explicitly opted back in.
if [[ "$LOAD_REASON" == "session_start" &&
  "${HOOK_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START:-false}" != "true" ]]; then
  exit 0
fi

SUBJECT="${FILE_PATH}:${LOAD_REASON}"

DATA=$(jq -nc --arg subject "$SUBJECT" '{subject: $subject}')

hook::emit_telemetry "instructions-loaded-audit" "InstructionsLoaded" "ok" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
