#!/usr/bin/env bash
# Stop hook: surface hook launch/exec failures that Claude Code records only as
# `hook_non_blocking_error` transcript attachments and shows to nobody (#2577).
#
# A hook that fails to LAUNCH is a non-blocking error: the tool call proceeds as
# if the hook had approved it, and the only durable trace is an attachment
# record in the session transcript that no human reads. The #1416 incident
# proved the class (a PreToolUse destructive guard dead for 140 recorded
# launches), and it also proved that an in-plugin detector is not shelter:
# disk-hygiene's own Stop-event `guard_launch_monitor.py` shared the guard's
# registration form and died the same launch death on all 23 of its runs. This
# hook is the DECOUPLED detector: it lives in a different plugin whose own
# registrations stayed alive through that entire incident, so a defect that
# kills a watched plugin's launch path does not take the detector with it. It
# also covers the stale-session window no source-side gate can reach: hook
# config is loaded at session start, so a session running when a fix lands on
# disk keeps executing the dead config until restart — 22 further failures were
# recorded in one live session AFTER the #2570 fix shipped (#2577).
#
# ADVISORY: never blocks, always exit 0. Registered on Stop, not
# PreToolUse/PostToolUse, for the cost rationale `guard_launch_monitor.py` and
# ADR 0004 (D-12) record: a failure record is already in the transcript by the
# time the turn ends, so once-per-turn cadence catches it as promptly as
# once-per-tool-call would at a fraction of the invocation count. The read is
# bounded (tail cap, truncated first line dropped) so per-turn cost is O(cap),
# not O(session length).
#
# Matching is STRUCTURAL, never substring: a record counts only when the
# top-level `.type == "attachment"` and `.attachment.type ==
# "hook_non_blocking_error"`. Two false-positive shapes make anything less
# strict wrong, both hit while mining the incident transcripts: a
# `hook_success` attachment whose stdout QUOTES an error, and a message record
# quoting a failure record as a plain string (#2577).
#
# Warns once per session PER DISTINCT failing hook name: the first Stop after a
# hook starts failing warns, later turns stay silent unless a NEW hook name
# starts failing. Marker bookkeeping degrades toward RE-WARNING, never toward
# silence — when no marker home is available the warning repeats rather than
# disappears, the same doctrine as `guard_launch_monitor.py`.
#
# Overlap with disk-hygiene's `guard_launch_monitor.py` is deliberate and
# accepted: that monitor keeps its guard-specific semantics; this one covers
# every hook of every plugin. A destructive-guard failure may be warned about
# twice — over-warning is the safe failure direction for this defect class.
#
# Kill switch: CLAUDE_PLUGIN_OPTION_HOOK_FAILURE_AUDIT_ENABLED=false.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "HOOK_FAILURE_AUDIT"

START=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0

# Advisory finding -> fail open, with the standard once-per-session notice.
hook::require_jq Stop claude-ops "$INPUT"

TRANSCRIPT=$(hook::jq_field "$INPUT" '.transcript_path') || exit 0
[[ -f "$TRANSCRIPT" ]] || exit 0
SESSION=$(hook::jq_field "$INPUT" '.session_id') || SESSION="no-session"
SESSION="${SESSION//[^A-Za-z0-9_-]/-}"

# Bounded tail read: cost stays O(cap) regardless of transcript growth. When
# the cap truncates, the first in-window line is likely partial — drop it, as
# guard_launch_monitor.py does. The override exists for the contract test.
TAIL_BYTES="${HOOK_FAILURE_AUDIT_TAIL_BYTES:-2000000}"
SIZE=$(wc -c <"$TRANSCRIPT" 2>/dev/null) || exit 0
read_window() {
  if ((SIZE > TAIL_BYTES)); then
    tail -c "$TAIL_BYTES" -- "$TRANSCRIPT" 2>/dev/null | sed '1d'
  else
    cat -- "$TRANSCRIPT" 2>/dev/null
  fi
}

# grep is a cheap pre-filter only; the structural jq selection decides.
# `fromjson?` skips unparsable lines instead of aborting the stream.
SUMMARY=$(read_window | grep -F '"hook_non_blocking_error"' |
  jq -cRs '[
      split("\n")[] | fromjson?
      | select(.type? == "attachment") | .attachment
      | select(.type? == "hook_non_blocking_error")
      | {hookName: (.hookName // "unknown"),
         stderr: ((.stderr // "") | .[0:160])}
    ]
    | group_by(.hookName)
    | map({hookName: .[0].hookName, count: length, stderr: .[-1].stderr})' 2>/dev/null)
[[ -n "$SUMMARY" && "$SUMMARY" != "[]" ]] || exit 0

# Once per session per hook name. Markers live under ${CLAUDE_PLUGIN_DATA}
# (survives plugin updates); stale sessions' markers are pruned after 7 days.
# Any bookkeeping failure leaves WARNED empty, so everything found is treated
# as new — re-warn, never suppress.
MARKER=""
WARNED=""
if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
  MARKER_DIR="${CLAUDE_PLUGIN_DATA}/hook-failure-audit"
  if mkdir -p "$MARKER_DIR" 2>/dev/null; then
    find "$MARKER_DIR" -type f -mtime +7 -delete 2>/dev/null
    MARKER="$MARKER_DIR/${SESSION}"
    [[ -f "$MARKER" ]] && WARNED=$(cat -- "$MARKER" 2>/dev/null)
  fi
fi

NEW=$(jq -cn --argjson summary "$SUMMARY" --arg warned "$WARNED" '
  ($warned | split("\n") | map(select(length > 0))) as $seen
  | [$summary[] | select(.hookName as $h | $seen | index($h) | not)]')
[[ -n "$NEW" && "$NEW" != "[]" ]] || exit 0

TOTAL=$(jq -rn --argjson new "$NEW" '[$new[].count] | add')
DETAIL=$(jq -rn --argjson new "$NEW" \
  '[$new[] | "\(.hookName) (\(.count)x; last stderr: \(.stderr))"] | join("; ")')

MSG="claude-ops: ${TOTAL} hook failure record(s) in this session's transcript were never surfaced: ${DETAIL}. A hook that fails to launch enforces nothing — the tool calls it guards proceed as if approved (fail-open). If a plugin update changed hook config on disk mid-session, this session still runs the config it loaded at startup — restart the session to load the fix."

hook::emit_system_message "$MSG"

# Record what was warned about before telemetry: the warning is the contract,
# the envelope is best-effort.
if [[ -n "$MARKER" ]]; then
  jq -rn --argjson new "$NEW" '$new[].hookName' >>"$MARKER" 2>/dev/null || true
fi

DATA=$(jq -cn --argjson new "$NEW" --argjson total "${TOTAL:-0}" \
  '{subjects: [$new[].hookName], total: $total}')
hook::emit_telemetry "hook-failure-audit" "Stop" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
