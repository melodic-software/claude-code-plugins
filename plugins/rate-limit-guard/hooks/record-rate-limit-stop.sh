#!/usr/bin/env bash
# StopFailure hook (matcher: rate_limit): append a machine-readable detection
# record when a turn ends on a rate-limit API error.
#
# SIDE-EFFECT-ONLY: the harness ignores StopFailure output and exit codes
# entirely (hooks reference, verified 2026-07-23), so this hook's one job is
# the record it appends — the reactive-fallback signal consumers read when the
# statusline tee carries no usable window data (see
# ../reference/reader-contract.md). The payload carries no reset or quota
# data; resume timing comes from the tee file or from error text the consuming
# session itself sees.
#
# Record sink: ~/.claude/rate-limit-guard/stop-events.jsonl — the fixed
# contract path (HOME-anchored, machine-scope, matching the tee file's
# single-account-per-machine invariant). Deliberately OUTSIDE
# ${CLAUDE_PLUGIN_DATA}: plugin data is cache-isolated per plugin, and this
# file is a documented cross-plugin artifact seam that sibling-plugin lane
# sessions must be able to read. One line per detection:
#   {"detected_at":"<ISO-8601 UTC>","hook_event_name":"StopFailure",
#    "matcher":"rate_limit","session_id":"<id, when present>"}
#
# jq-FREE by design: a rate-limit stop is exactly when the environment is
# least trustworthy, so the record is hand-built with the lib's JSON escaper
# and session_id is regex-extracted. Empty or unparsable stdin still records —
# the event firing is itself the signal. The file is rotated in place (keep
# the newest 100 once it exceeds 200 lines) so it cannot grow unboundedly.
#
# Kill switch: rate_limit_guard_enabled userConfig boolean, read via the
# CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED hook-process mirror.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "RATE_LIMIT_GUARD"

# Buffer stdin once (Win32-pipe-safe bounded read). A missing or incomplete
# payload degrades the record, never suppresses it.
INPUT=$(hook::buffer_stdin) || INPUT=""

SESSION=""
if [[ "$INPUT" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]]; then
  SESSION="${BASH_REMATCH[1]}"
fi

# silent-skip-ok: no HOME means no resolvable contract path anywhere on this
# host — nothing this hook could usefully write, and StopFailure has no
# visible output channel to report through (output is ignored by contract).
[[ -n "${HOME:-}" ]] || exit 0
GUARD_DIR="$HOME/.claude/rate-limit-guard"
EVENTS="$GUARD_DIR/stop-events.jsonl"
# silent-skip-ok: an uncreatable contract dir cannot be surfaced from a
# StopFailure hook (output and exit code are ignored); the setup skill's
# check probe is the visibility surface for a broken contract path.
mkdir -p "$GUARD_DIR" 2>/dev/null || exit 0
# Owner-only contract dir + owner-only files from here on (records, lock,
# rotation temp). Best-effort on filesystems without POSIX modes.
chmod 700 "$GUARD_DIR" 2>/dev/null || true
umask 077

ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts=""

record='{"detected_at":"'"$(hook::json_escape "$ts")"'","hook_event_name":"StopFailure","matcher":"rate_limit"'
if [[ -n "$SESSION" ]]; then
  # SESSION is captured between unescaped quotes of a JSON string token, so
  # it is already JSON-escaped text and re-escaping would double the
  # backslashes. The record's validity therefore also leans on the emitter
  # having produced RFC-valid JSON (the harness does): a raw control byte
  # inside the source value would carry through and break this JSONL line.
  # Not adversary-reachable via well-formed hook input, but not
  # unconditionally safe either — consumers parse records with a JSON
  # parser and skip lines that fail to parse.
  record+=',"session_id":"'"$SESSION"'"'
fi
record+='}'

hook::append_jsonl "$EVENTS" "$record"

# Bound the file at ~200 records, keeping the newest 100.
rotate_events() {
  local lines tmp
  lines=$(wc -l <"$EVENTS" 2>/dev/null | tr -d ' \r') || return 0
  [[ "$lines" =~ ^[0-9]+$ ]] || return 0
  ((lines > 200)) || return 0
  tmp="$EVENTS.tmp.$$"
  if tail -n 100 "$EVENTS" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$EVENTS" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# Rotation runs under the SAME advisory lock hook::append_jsonl uses (the
# sibling .lock file), so a record another session appends mid-rotation is
# never dropped by the tail+rename. Without flock the append itself is
# already best-effort, and so is this — a lost race there costs at most a
# few advisory records, never this process's own (already appended above).
if command -v flock >/dev/null 2>&1; then
  (
    flock -w 2 9 || exit 0
    rotate_events
  ) 9>"$EVENTS.lock" 2>/dev/null
else
  rotate_events
fi

exit 0
