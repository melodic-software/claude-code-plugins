#!/usr/bin/env bash

set -uo pipefail

CG_DIR=${BASH_SOURCE[0]%/*}
[[ "$CG_DIR" == "${BASH_SOURCE[0]}" ]] && CG_DIR=.
[[ "${CLAUDE_PLUGIN_OPTION_CONTEXT_USAGE_HOOKS_ENABLED:-true}" == "true" ]] || exit 0
# shellcheck source=hook-utils.sh
source "$CG_DIR/hook-utils.sh"
# shellcheck source=payload.sh
source "$CG_DIR/payload.sh"

START_EPOCH=${EPOCHREALTIME:-0}

INPUT=$(cg::read_payload) || INPUT=""

# Claude Code sets agent_id when a subagent compacts, and that leaves the main
# session's context whole: https://code.claude.com/docs/en/changelog#2-1-323
[[ "$INPUT" =~ \"agent_id\"[[:space:]]*:[[:space:]]*\"[^\"] ]] && exit 0

SESSION=""
if [[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
  SESSION="${BASH_REMATCH[1]}"
fi
[[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0

TRIGGER="unknown"
if [[ "$INPUT" =~ \"trigger\"[[:space:]]*:[[:space:]]*\"(manual|auto)\" ]]; then
  TRIGGER="${BASH_REMATCH[1]}"
fi

[[ -n "${HOME:-}" ]] || exit 0
CTX_DIR="$HOME/.claude/context-usage/context"
[[ -d "$CTX_DIR" ]] || mkdir -p "$CTX_DIR" 2>/dev/null || exit 0
chmod 700 "$HOME/.claude/context-usage" "$CTX_DIR" 2>/dev/null || true
umask 077

ts=""
if ! TZ=UTC printf -v ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || [[ -z "$ts" ]]; then
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts=""
fi

marker='{"compacted_at":"'"$(hook::json_escape "$ts")"'","trigger":"'"$TRIGGER"'","hook_event_name":"PostCompact"}'
target="$CTX_DIR/$SESSION.compacted"
tmp="$CTX_DIR/$SESSION.compacted.tmp.$$"
telemetry_status="error"
if printf '%s\n' "$marker" >"$tmp" 2>/dev/null; then
  if [[ ! -d "$target" ]] && mv -f "$tmp" "$target" 2>/dev/null; then
    telemetry_status="ok"
  else
    rm -f "$tmp" 2>/dev/null
  fi
fi

find "$CTX_DIR" -maxdepth 1 -name '*.compacted' -mmin +20160 -exec rm -f {} + 2>/dev/null || true

hook::emit_telemetry "post-compact-mark" "PostCompact" "$telemetry_status" "$START_EPOCH" \
  '{"trigger":"'"$TRIGGER"'"}'
exit 0
