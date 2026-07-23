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

ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null) || ts=""

record='{"detected_at":"'"$(hook::json_escape "$ts")"'","hook_event_name":"StopFailure","matcher":"rate_limit"'
if [[ -n "$SESSION" ]]; then
  # SESSION is captured from the raw JSON between unescaped quotes, so it is
  # already JSON-escaped text; re-escaping would double the backslashes.
  record+=',"session_id":"'"$SESSION"'"'
fi
record+='}'

hook::append_jsonl "$EVENTS" "$record"

# Best-effort rotation: bound the file at ~200 records, keeping the newest
# 100. Advisory data — a lost race with a concurrent writer costs at most a
# few records, never the newest one on this path.
lines=$(wc -l <"$EVENTS" 2>/dev/null | tr -d ' \r') || lines=""
if [[ "$lines" =~ ^[0-9]+$ ]] && ((lines > 200)); then
  tmp="$EVENTS.tmp.$$"
  if tail -n 100 "$EVENTS" >"$tmp" 2>/dev/null; then
    mv -f "$tmp" "$EVENTS" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
fi

exit 0
