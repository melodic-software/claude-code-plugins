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
# Warns once per session PER DISTINCT failing hook REGISTRATION, identified by
# (hookName, command) — hookName alone is just event:matcher, which several
# plugins share: the first Stop after a registration starts failing warns,
# later turns stay silent unless a NEW registration starts failing. Marker
# bookkeeping degrades toward RE-WARNING, never toward silence — when no marker
# home is available the warning repeats rather than disappears, the same
# doctrine as `guard_launch_monitor.py`.
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
# Identity is the REGISTRATION, not the matcher name: several plugins register
# on the same event+matcher (multiple PreToolUse:Bash guards exist in this very
# marketplace), and the attachment's command string is what tells them apart —
# grouping by hookName alone would let registration B's first failure hide
# behind registration A's earlier warning.
#
# `launch` classifies the record: a hook that never LAUNCHED and one that RAN
# and exited non-zero are different incidents with different remedies, and only
# the first is fixed by restarting the session (#2849). `exitCode` alone cannot
# carry the split — every record in the observed corpus has a non-null exitCode
# (175/175 on 2026-08-16), and 1 is the code the WSL relay reports for its exec
# failures, so "exitCode is not null" and "exitCode != 1" both misclassify. The
# discriminator is the shell's own exec-failure surface: 126/127, or an
# exec-failure signature in stderr. The signature set stays narrow on purpose —
# `command not found` and `cannot execute` are excluded because a hook that
# launched fine can print either from a command it ran itself, which would
# re-introduce this defect in a new shape; 126/127 already cover those for the
# hook's own command. Classification reads the FULL stderr, before the 160-char
# truncation below: the observed `execvpe` signature sits at offset 90-94 and
# survives truncation today, but that is luck, not contract.
SUMMARY=$(read_window | grep -F '"hook_non_blocking_error"' |
  jq -cRs '[
      split("\n")[] | fromjson?
      | select(.type? == "attachment") | .attachment
      | select(.type? == "hook_non_blocking_error")
      | {hookName: (.hookName // "unknown"),
         command: ((.command // "") | .[0:120]),
         exitCode: (.exitCode // null),
         launch: ((.exitCode == 126 or .exitCode == 127)
                  or ((.stderr // "")
                      | test("execvpe|execve\\(|exec format error|not recognized as an internal or external command"; "i"))),
         stderr: ((.stderr // "") | .[0:160])}
    ]
    | group_by(.hookName + "	" + .command)
    | map({hookName: .[0].hookName, command: .[0].command,
           count: length, exitCode: last.exitCode, launch: last.launch,
           stderr: last.stderr})' 2>/dev/null)
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

# Marker lines are "<hookName>\t<command>" fingerprints. `rtrimstr("\r")` on
# read and `tr -d '\r'` on write: some Windows jq builds emit CRLF, and a
# fingerprint that grows a carriage return on one side of the comparison would
# quietly re-warn (or worse, wrongly suppress) forever after.
NEW=$(jq -cn --argjson summary "$SUMMARY" --arg warned "$WARNED" '
  ($warned | split("\n") | map(rtrimstr("\r")) | map(select(length > 0))) as $seen
  | [$summary[] | select((.hookName + "	" + .command) as $k | $seen | index($k) | not)]')
[[ -n "$NEW" && "$NEW" != "[]" ]] || exit 0

TOTAL=$(jq -rn --argjson new "$NEW" '[$new[].count] | add')

# Claude Code synthesizes this exact sentence as the stderr of a hook that
# produced none, so an empty `.stderr` is a shape the harness does not emit —
# 0 of 175 observed records carry one, while 12 carry this literal (#2849).
# Passing it through verbatim reads as though the HOOK emitted the sentence;
# both shapes are rendered as the same explicit no-output marker instead. The
# match is exact, not a prefix: the string is the whole stderr in every
# observed record (12/12 exact, 0 needing whitespace trimming).
NO_STDERR_PLACEHOLDER='Failed with non-blocking status code: No stderr output'

DETAIL=$(jq -rn --argjson new "$NEW" --arg ph "$NO_STDERR_PLACEHOLDER" '
  [$new[] |
    (if (.stderr == "" or .stderr == $ph) then "(none — hook produced no stderr)"
     else .stderr end) as $err |
    (if .exitCode == null then "?" else (.exitCode|tostring) end) as $ec |
    (if .launch then "launch failure" else "completed non-zero exit" end) as $kind |
    "\(.hookName) [\(.command)] (\(.count)x; \($kind); exit \($ec); last stderr: \($err))"
  ] | join("; ")')

HAS_LAUNCH=$(jq -rn --argjson new "$NEW" '[$new[].launch] | any')
HAS_COMPLETED=$(jq -rn --argjson new "$NEW" '[$new[].launch | not] | any')

# The diagnosis and the remedy are per-class, so both sentences can appear when
# one warning batches records of both classes; the per-record `$kind` above says
# which record earned which. The launch-failure wording is kept VERBATIM where
# it is correct — it is right for the 164 exec-failure records in the observed
# corpus — and is simply not asserted about a hook that ran to completion. The
# completed branch stays event-agnostic: 2593's record is a Stop hook, where
# there is no guarded tool call to proceed.
MSG="claude-ops: ${TOTAL} hook failure record(s) in this session's transcript were never surfaced: ${DETAIL}."
if [[ "$HAS_LAUNCH" == "true" ]]; then
  MSG="${MSG} A hook that fails to launch enforces nothing — the tool calls it guards proceed as if approved (fail-open)."
fi
if [[ "$HAS_COMPLETED" == "true" ]]; then
  MSG="${MSG} A hook that ran to completion and exited non-zero enforced nothing either, and Claude Code told nobody — but it did launch, so the failure is in the hook's own logic: read the exit status and stderr above."
fi
MSG="${MSG} Confirm hook_failure_audit_enabled stays true via /plugin configure claude-ops@<marketplace> (default true)."
if [[ "$HAS_LAUNCH" == "true" ]]; then
  MSG="${MSG} If a plugin update changed hook config on disk mid-session, this session still runs the config it loaded at startup — restart the session to load the fix."
fi

hook::emit_system_message "$MSG"

# Record what was warned about before telemetry: the warning is the contract,
# the envelope is best-effort.
if [[ -n "$MARKER" ]]; then
  jq -rn --argjson new "$NEW" '$new[] | .hookName + "	" + .command' 2>/dev/null |
    tr -d '\r' >>"$MARKER" || true
fi

# Telemetry subjects stay hookName-only (privacy-safe); the command detail is
# user-facing message content, not envelope data.
DATA=$(jq -cn --argjson new "$NEW" --argjson total "${TOTAL:-0}" \
  '{subjects: ([$new[].hookName] | unique), total: $total}')
hook::emit_telemetry "hook-failure-audit" "Stop" "error" \
  "$START" "$DATA" "${CLAUDE_PROJECT_DIR:-}"

exit 0
