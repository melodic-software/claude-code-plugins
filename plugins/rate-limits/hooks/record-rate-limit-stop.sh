#!/usr/bin/env bash
set -uo pipefail
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

[[ "${CLAUDE_PLUGIN_OPTION_RATE_LIMITS_ENABLED:-true}" == "true" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"

hook::buffer_stdin_to INPUT || INPUT=""

SESSION=""
if [[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
  SESSION="${BASH_REMATCH[1]}"
fi

[[ -n "${HOME:-}" ]] || exit 0
CONTRACT_DIR="$HOME/.claude/rate-limits"
EVENTS="$CONTRACT_DIR/stop-events.jsonl"
mkdir -p "$CONTRACT_DIR" 2>/dev/null || exit 0
chmod 700 "$CONTRACT_DIR" 2>/dev/null || true
umask 077

ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts=""

record='{"detected_at":"'"$(hook::json_escape "$ts")"'","hook_event_name":"StopFailure","matcher":"rate_limit"'
if [[ -n "$SESSION" ]]; then
  record+=',"session_id":"'"$SESSION"'"'
fi
record+='}'

hook::append_jsonl "$EVENTS" "$record"

rotate_events() {
  local lines tmp
  lines=$(wc -l <"$EVENTS" 2>/dev/null) || return 0
  lines="${lines//[ $'\r']/}"
  [[ "$lines" =~ ^[0-9]+$ ]] || return 0
  ((lines > 200)) || return 0
  tmp="$EVENTS.tmp.$$"
  if ! tail -n 100 "$EVENTS" >"$tmp" 2>/dev/null || ! mv -f "$tmp" "$EVENTS" 2>/dev/null; then
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

if command -v flock >/dev/null 2>&1; then
  (
    flock -w 2 9 || exit 0
    rotate_events
  ) 9>"$EVENTS.lock" 2>/dev/null
else
  rotate_events
fi

exit 0
