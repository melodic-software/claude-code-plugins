#!/usr/bin/env bash
# InstructionsLoaded hook: emit a telemetry envelope for rule/instruction file
# loads. Lets a consumer validate that `paths:` frontmatter is matching and
# @-includes resolve (which rules actually load).
#
# ADVISORY: InstructionsLoaded exit code is ignored — always exit 0.
# The subject is "<repo-relative-file>:<load_reason>" so query analysis can group
# loads by reason without parsing extra fields. The path is reduced to a
# repo-relative form (or basename) — the absolute prefix is never captured.
#
# Write-time filter: session_start loads are deterministic (the same always-load
# files fire every boot) and high-volume, so they are dropped by default. Opt
# back in for one-off debugging with:
#   CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START=true
#
# Pure telemetry emitter: no sink wired (HOOK_TELEMETRY_SINK unset) → no-op.
# Kill switches:
#   CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_ENABLED=false           — disable entirely
#   CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START=true   — opt back into session_start

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "INSTRUCTIONS_LOADED_AUDIT"
hook::telemetry_enabled || exit 0

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

FILE_PATH=$(hook::jq_field "$INPUT" '.file_path' || true)
LOAD_REASON=$(hook::jq_field "$INPUT" '.load_reason' || true)

# Need at least one of the two; a pure missing payload is a silent skip.
[[ -n "$FILE_PATH$LOAD_REASON" ]] || exit 0

# Drop session_start at write time unless explicitly opted back in.
if [[ "$LOAD_REASON" == "session_start" &&
  "${CLAUDE_PLUGIN_OPTION_INSTRUCTIONS_LOADED_AUDIT_LOG_SESSION_START:-false}" != "true" ]]; then
  exit 0
fi

# Privacy: InstructionsLoaded `file_path` is absolute, so logging it verbatim
# would leak local usernames / private directory names into the shared
# observability store. Reduce to a repo-relative path when the file is under the
# project root, else to its basename — never the absolute prefix.
FILE_DISP=""
if [[ -n "$FILE_PATH" ]]; then
  project_dir=$(hook::repo_root "${CLAUDE_PROJECT_DIR:-.}")
  case "$FILE_PATH" in
  "$project_dir"/*) FILE_DISP="${FILE_PATH#"$project_dir"/}" ;;
  *) FILE_DISP="${FILE_PATH##*/}" ;;
  esac
fi

SUBJECT="${FILE_DISP}:${LOAD_REASON}"

DATA=$(jq -nc --arg subject "$SUBJECT" '{subject: $subject}')

hook::emit_telemetry "instructions-loaded-audit" "InstructionsLoaded" "ok" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
