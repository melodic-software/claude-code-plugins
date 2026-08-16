#!/usr/bin/env bash
# Contract test for hook-failure-audit.sh (claude-ops plugin). Black-box.
#
# The fixture failure record is a structural copy of a REAL transcript
# attachment from the #1416/#2577 incident host (session ac1c95e3, 2026-08-13):
# a disk-hygiene destructive-guard registration resolving `bash` to the Windows
# WSL relay and dying at launch. The two false-positive shapes asserted below
# (a `hook_success` quoting an error in stdout, and a message record quoting a
# failure record as a string) are the exact traps hit while mining the incident
# transcripts — see #2577.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/hook-failure-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=claude-ops-test-helpers.sh
source "$HOOK_DIR/claude-ops-test-helpers.sh"
unset CLAUDE_PROJECT_DIR

WSL_STDERR='Failed with non-blocking status code: <3>WSL (10 - Relay) ERROR: CreateProcessCommon:818: execvpe(/bin/bash) failed: No such file or directory'

# One transcript line per record, matching the real attachment envelope shape.
failure_record() { # <hookName> <command>
  printf '{"parentUuid":"p","isSidechain":false,"attachment":{"type":"hook_non_blocking_error","hookName":"%s","toolUseID":"toolu_x","hookEvent":"PreToolUse","stderr":"%s","stdout":"","exitCode":1,"command":"%s","durationMs":2080},"type":"attachment","uuid":"u","timestamp":"2026-08-13T13:56:38.155Z","session_id":"s","sessionId":"s","version":"2.1.228"}\n' \
    "$1" "${WSL_STDERR//\"/\\\"}" "$2"
}

make_transcript() { # <path> — base fixture: 1 real failure + both false-positive shapes
  local t="$1"
  {
    # Truncated first line, as a bounded tail read would produce.
    printf 'garbage-not-json {"half": \n'
    failure_record "PreToolUse:Bash" "bash \${CLAUDE_PLUGIN_ROOT}/hooks/run-python-hook.sh"
    # FALSE POSITIVE 1: a hook_success whose stdout QUOTES the failure text.
    printf '{"attachment":{"type":"hook_success","hookName":"PostToolUse:Edit","stdout":"saw hook_non_blocking_error and %s in a log","stderr":"","exitCode":0},"type":"attachment","uuid":"u2","session_id":"s"}\n' "${WSL_STDERR//\"/\\\"}"
    # FALSE POSITIVE 2: an assistant message quoting a failure record as a STRING.
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"sample: {\\"type\\": \\"hook_non_blocking_error\\", \\"hookName\\": \\"PreToolUse:QuotedOnly\\"}"}]},"uuid":"u3","session_id":"s"}\n'
  } >"$t"
}

# Execute the script DIRECTLY, the way the hooks.json registration invokes it
# (no `bash` prefix) — so a non-executable committed mode fails here the same
# way it would fail in production (exit 126) instead of being masked by an
# explicit interpreter.
run_hook() { # <transcript> <data_dir> [extra env pairs...]
  local transcript="$1" data_dir="$2"
  shift 2
  env CLAUDE_PLUGIN_DATA="$data_dir" "$@" "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$transcript\",\"hook_event_name\":\"Stop\"}" 2>&1
}

# --- Red-first core: a real launch-failure record is surfaced ---------------
T1="$TEST_TMPDIR/t1.jsonl"
make_transcript "$T1"
DATA1="$TEST_TMPDIR/data1"
OUT=$(run_hook "$T1" "$DATA1")
RC=$?
assert_exit "failure surfaced -> exit 0" 0 "$RC"
assert_contains "names the dead hook" "$OUT" "PreToolUse:Bash"
assert_contains "systemMessage emitted" "$OUT" "systemMessage"
assert_contains "explains fail-open" "$OUT" "fail-open"
assert_contains "stale-session guidance" "$OUT" "restart"

# --- Structural matching: neither false-positive shape fires ----------------
assert_absent "hook_success quoting an error does not fire" "$OUT" "PostToolUse:Edit"
assert_absent "string-quoted record does not fire" "$OUT" "PreToolUse:QuotedOnly"

# --- Once per session per hook: second run is silent ------------------------
OUT2=$(run_hook "$T1" "$DATA1")
RC2=$?
assert_exit "dedup run -> exit 0" 0 "$RC2"
assert_silent "same failures already warned -> silent" "$OUT2"

# --- A NEW failing hook re-warns, already-warned hooks stay muted -----------
failure_record "SessionStart" "node missing-lifecycle-hook.mjs" >>"$T1"
OUT3=$(run_hook "$T1" "$DATA1")
assert_contains "new failing hook warned" "$OUT3" "SessionStart"
assert_absent "already-warned hook muted" "$OUT3" "PreToolUse:Bash"

# --- Distinct registrations sharing a hookName are distinct failures --------
# Multiple plugins register on the same event+matcher (e.g. several
# PreToolUse:Bash guards); the attachment's command is what tells them apart.
# A second registration failing later in the session must re-warn even though
# the first already wrote this hookName to the marker.
failure_record "PreToolUse:Bash" "other-plugin-guard.sh --different-registration" >>"$T1"
OUT3B=$(run_hook "$T1" "$DATA1")
assert_contains "same hookName, new registration -> re-warns" "$OUT3B" "other-plugin-guard.sh"
OUT3C=$(run_hook "$T1" "$DATA1")
assert_silent "both registrations warned -> silent" "$OUT3C"

# --- No CLAUDE_PLUGIN_DATA: degrade toward re-warning, never silence --------
T2="$TEST_TMPDIR/t2.jsonl"
make_transcript "$T2"
OUT4=$(env -u CLAUDE_PLUGIN_DATA bash "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$T2\",\"hook_event_name\":\"Stop\"}" 2>&1)
assert_contains "no marker home -> still warns" "$OUT4" "PreToolUse:Bash"
OUT5=$(env -u CLAUDE_PLUGIN_DATA bash "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$T2\",\"hook_event_name\":\"Stop\"}" 2>&1)
assert_contains "no marker home -> re-warns rather than suppresses" "$OUT5" "PreToolUse:Bash"

# --- Launch failure vs completed non-zero exit are DIFFERENT diagnoses ------
# #2849: the "fails to launch" sentence was unconditional, so a hook that ran
# to completion and exited non-zero was told it never launched and was handed a
# restart-the-session remedy that changes nothing for it. The corpus behind that
# issue (175 records, 2026-08-16) has zero records with an EMPTY stderr — the
# harness synthesizes a sentence instead — so the empty-stderr placeholder the
# #2593 fix shipped never fired, and the synthesized sentence reached operators
# verbatim as though the hook had emitted it.
HARNESS_NO_STDERR='Failed with non-blocking status code: No stderr output'

custom_record() { # <hookName> <command> <stderr> <exitCode> <durationMs>
  printf '{"parentUuid":"p","isSidechain":false,"attachment":{"type":"hook_non_blocking_error","hookName":"%s","toolUseID":"toolu_x","hookEvent":"Stop","stderr":"%s","stdout":"","exitCode":%s,"command":"%s","durationMs":%s},"type":"attachment","uuid":"u","timestamp":"2026-08-13T13:56:38.155Z","session_id":"s","sessionId":"s","version":"2.1.228"}\n' \
    "$1" "${3//\"/\\\"}" "$4" "$2" "$5"
}

# 2593's own record: ran 1190 ms, exited 1, carrying the harness placeholder.
T_DONE="$TEST_TMPDIR/completed.jsonl"
custom_record "Stop:ran-and-failed" "node stop-hook.mjs" "$HARNESS_NO_STDERR" 1 1190 >"$T_DONE"
OUT_DONE=$(run_hook "$T_DONE" "$TEST_TMPDIR/data-done")
RC_DONE=$?
assert_exit "completed non-zero exit -> exit 0" 0 "$RC_DONE"
assert_contains "completed record is still surfaced" "$OUT_DONE" "Stop:ran-and-failed"
assert_contains "diagnosed as a completed non-zero exit" "$OUT_DONE" "completed non-zero exit"
assert_absent "not described as a launch failure" "$OUT_DONE" "fails to launch"
assert_absent "no restart-the-session remedy" "$OUT_DONE" "restart"
assert_absent "harness placeholder not attributed to the hook" "$OUT_DONE" "$HARNESS_NO_STDERR"
assert_contains "no-stderr rendered as an explicit marker" "$OUT_DONE" "last stderr: (none — hook produced no stderr)"

# A real hook stderr must survive untouched — the placeholder rewrite is keyed
# on the harness's exact sentence, not on "looks like there was no output".
# Quote-free so the assertion compares the message text itself rather than the
# emitting envelope's JSON escaping of it.
REAL_STDERR='TypeError: Cannot read properties of undefined (reading cwd) at hooks/broken-stop.mjs:42:11'
T_REAL="$TEST_TMPDIR/real-stderr.jsonl"
custom_record "Stop:threw" "node broken-stop.mjs" "$REAL_STDERR" 1 640 >"$T_REAL"
OUT_REAL=$(run_hook "$T_REAL" "$TEST_TMPDIR/data-real")
assert_contains "real stderr passed through unchanged" "$OUT_REAL" "$REAL_STDERR"
assert_absent "real stderr not replaced by the no-output marker" "$OUT_REAL" "hook produced no stderr"
assert_absent "a hook that ran and threw is not a launch failure" "$OUT_REAL" "fails to launch"

# SIGNATURE EVIDENCE decides the launch-failure label, regardless of exit code.
# The observed corpus makes the code and the signature close to independent: 163
# records carry an `execvpe` signature at exitCode 1, and the single exitCode 127
# record carries no stderr signature at all.
T_EXECVPE="$TEST_TMPDIR/execvpe.jsonl"
custom_record "PreToolUse:Bash" "bash relay-guard.sh" "$WSL_STDERR" 1 8 >"$T_EXECVPE"
OUT_EXECVPE=$(run_hook "$T_EXECVPE" "$TEST_TMPDIR/data-execvpe")
assert_contains "execvpe at exit 1 is still a launch failure" "$OUT_EXECVPE" "launch failure"
assert_contains "execvpe keeps the fails-to-launch wording" "$OUT_EXECVPE" "fails to launch"
assert_contains "execvpe keeps the restart remedy" "$OUT_EXECVPE" "restart"
assert_absent "execvpe at exit 1 is not called ambiguous" "$OUT_EXECVPE" "ambiguous"

# A signature AT 126/127 is a launch failure outright — the signature decides,
# so the ambiguity below is only ever about a code with no signature behind it.
T_SIG127="$TEST_TMPDIR/sig127.jsonl"
custom_record "PreToolUse:Bash" "bash relay-guard.sh" "$WSL_STDERR" 127 8 >"$T_SIG127"
OUT_SIG127=$(run_hook "$T_SIG127" "$TEST_TMPDIR/data-sig127")
assert_contains "signature at exit 127 is a launch failure" "$OUT_SIG127" "launch failure"
assert_absent "signature at exit 127 is not ambiguous" "$OUT_SIG127" "ambiguous"

T_SIG126="$TEST_TMPDIR/sig126.jsonl"
custom_record "PreToolUse:Bash" "./guard.sh" "bash: ./guard.sh: exec format error" 126 4 >"$T_SIG126"
OUT_SIG126=$(run_hook "$T_SIG126" "$TEST_TMPDIR/data-sig126")
assert_contains "signature at exit 126 is a launch failure" "$OUT_SIG126" "launch failure"
assert_absent "signature at exit 126 is not ambiguous" "$OUT_SIG126" "ambiguous"

# A BARE 126/127 with no signature is AMBIGUOUS, not a launch failure. A
# registered shell hook launches fine and still exits 126/127 when a command
# INSIDE it is not invocable, so the code alone cannot carry the split; asserting
# a launch failure there hands out the restart remedy for a defect restarting
# cannot touch, which is the misdiagnosis #2849 exists to fix. This deliberately
# refines acceptance criterion 2 of #2849 (126/127 OR a signature keeps the
# launch wording) — see the PR body and the CHANGELOG.
T_127="$TEST_TMPDIR/exit127.jsonl"
custom_record "PreToolUse:Bash" "missing-binary --guard" "$HARNESS_NO_STDERR" 127 12 >"$T_127"
OUT_127=$(run_hook "$T_127" "$TEST_TMPDIR/data-127")
assert_contains "bare exit 127 is reported ambiguous" "$OUT_127" \
  "ambiguous: exit 126/127 with no exec-failure signature"
assert_contains "bare exit 127 says both readings are possible" "$OUT_127" "Both are possible"
assert_absent "bare exit 127 is not asserted to be a launch failure" "$OUT_127" "fails to launch"
assert_absent "bare exit 127 is not asserted to have completed" "$OUT_127" "no exec-failure evidence"
assert_contains "bare exit 127 still offers the restart remedy" "$OUT_127" "restart"
assert_contains "bare exit 127 also points at the hook's own commands" "$OUT_127" \
  "read the hook's own logic"

T_126="$TEST_TMPDIR/exit126.jsonl"
custom_record "PreToolUse:Bash" "not-executable-guard.sh" "$HARNESS_NO_STDERR" 126 9 >"$T_126"
OUT_126=$(run_hook "$T_126" "$TEST_TMPDIR/data-126")
assert_contains "bare exit 126 is reported ambiguous" "$OUT_126" \
  "ambiguous: exit 126/127 with no exec-failure signature"
assert_absent "bare exit 126 is not asserted to be a launch failure" "$OUT_126" "fails to launch"
assert_absent "bare exit 126 is not asserted to have completed" "$OUT_126" "no exec-failure evidence"
assert_contains "bare exit 126 still offers the restart remedy" "$OUT_126" "restart"

# A hook that LAUNCHED and whose own subcommand was missing must NOT be called a
# launch failure. cmd.exe's not-found phrasing is the Windows spelling of
# "command not found", and a launched hook prints it about a command IT ran; the
# discriminator excludes it for the same reason it excludes the POSIX spelling.
T_SUBCMD="$TEST_TMPDIR/missing-subcommand.jsonl"
custom_record "Stop:lint" "bash lint-stop.sh" \
  "'ripgrep' is not recognized as an internal or external command, operable program or batch file." \
  1 800 >"$T_SUBCMD"
OUT_SUBCMD=$(run_hook "$T_SUBCMD" "$TEST_TMPDIR/data-subcmd")
assert_contains "missing subcommand is a completed non-zero exit" "$OUT_SUBCMD" "completed non-zero exit"
assert_absent "missing subcommand is not a launch failure" "$OUT_SUBCMD" "fails to launch"
assert_absent "missing subcommand gets no restart remedy" "$OUT_SUBCMD" "restart"

# A record whose exitCode is absent must not be told it launched: the hook has
# no evidence either way, so the completed-branch wording asserts only the
# absence of exec-failure evidence, never a positive launch.
T_NOEC="$TEST_TMPDIR/no-exitcode.jsonl"
printf '{"attachment":{"type":"hook_non_blocking_error","hookName":"Stop:noexit","stderr":"something went wrong","stdout":"","command":"bash mystery.sh","durationMs":50},"type":"attachment","uuid":"u","session_id":"s"}\n' >"$T_NOEC"
OUT_NOEC=$(run_hook "$T_NOEC" "$TEST_TMPDIR/data-noec")
assert_contains "absent exitCode still surfaced" "$OUT_NOEC" "Stop:noexit"
assert_contains "absent exitCode renders as unknown" "$OUT_NOEC" "exit ?"
assert_absent "absent exitCode is not asserted to have launched" "$OUT_NOEC" "it did launch"

# ONE registration failing BOTH ways in the same unwarned batch. group_by
# collapses these two records into a single detail line, so a class read off the
# LAST record alone would relabel the whole 2x group by whichever record came
# last and would drop the other class's sentence from the message entirely. Both
# orderings are asserted: the bug is directional, and either order hides it.
for ORDER in launch-first completed-first; do
  T_MIX="$TEST_TMPDIR/mixed-$ORDER.jsonl"
  if [[ "$ORDER" == "launch-first" ]]; then
    {
      custom_record "PreToolUse:Bash" "bash flaky-guard.sh" "$WSL_STDERR" 1 6
      custom_record "PreToolUse:Bash" "bash flaky-guard.sh" "$REAL_STDERR" 1 940
    } >"$T_MIX"
  else
    {
      custom_record "PreToolUse:Bash" "bash flaky-guard.sh" "$REAL_STDERR" 1 940
      custom_record "PreToolUse:Bash" "bash flaky-guard.sh" "$WSL_STDERR" 1 6
    } >"$T_MIX"
  fi
  OUT_MIX=$(run_hook "$T_MIX" "$TEST_TMPDIR/data-mixed-$ORDER")
  assert_contains "$ORDER: both records counted" "$OUT_MIX" "(2x;"
  assert_contains "$ORDER: label names both classes" "$OUT_MIX" \
    "1 launch failure + 1 completed non-zero exit"
  assert_contains "$ORDER: launch diagnosis kept" "$OUT_MIX" "fails to launch"
  assert_contains "$ORDER: launch remedy kept" "$OUT_MIX" "restart"
  assert_contains "$ORDER: completed diagnosis kept" "$OUT_MIX" "no exec-failure evidence"
done

# The same collapse, now across all THREE classes. The ambiguous record is placed
# FIRST in one ordering and LAST in the other, so a class read off `last` — or a
# message flag derived from a collapsed value rather than from the per-record
# counts — loses a different class in each direction.
for ORDER in ambiguous-first ambiguous-last; do
  T_MIX3="$TEST_TMPDIR/mixed3-$ORDER.jsonl"
  if [[ "$ORDER" == "ambiguous-first" ]]; then
    {
      custom_record "PreToolUse:Bash" "bash tri-guard.sh" "$HARNESS_NO_STDERR" 127 3
      custom_record "PreToolUse:Bash" "bash tri-guard.sh" "$WSL_STDERR" 1 6
      custom_record "PreToolUse:Bash" "bash tri-guard.sh" "$REAL_STDERR" 1 940
    } >"$T_MIX3"
  else
    {
      custom_record "PreToolUse:Bash" "bash tri-guard.sh" "$REAL_STDERR" 1 940
      custom_record "PreToolUse:Bash" "bash tri-guard.sh" "$WSL_STDERR" 1 6
      custom_record "PreToolUse:Bash" "bash tri-guard.sh" "$HARNESS_NO_STDERR" 127 3
    } >"$T_MIX3"
  fi
  OUT_MIX3=$(run_hook "$T_MIX3" "$TEST_TMPDIR/data-mixed3-$ORDER")
  assert_contains "$ORDER: all three records counted" "$OUT_MIX3" "(3x;"
  assert_contains "$ORDER: label names all three classes" "$OUT_MIX3" \
    "1 launch failure + 1 ambiguous: exit 126/127 with no exec-failure signature + 1 completed non-zero exit"
  assert_contains "$ORDER: launch diagnosis kept" "$OUT_MIX3" "fails to launch"
  assert_contains "$ORDER: ambiguous diagnosis kept" "$OUT_MIX3" "Both are possible"
  assert_contains "$ORDER: completed diagnosis kept" "$OUT_MIX3" "no exec-failure evidence"
  assert_contains "$ORDER: restart remedy kept" "$OUT_MIX3" "restart"
done

# The maintainer-facing prose describing the #2593 fix is gone from the
# operator-facing message (#2849).
assert_absent "no maintainer-facing implementation prose" "$OUT_EXECVPE" "empty-stderr placeholder"
assert_absent "no maintainer-facing implementation prose (completed)" "$OUT_DONE" "empty-stderr placeholder"

# --- Bounded tail: a failure pushed past the window is not read -------------
T3="$TEST_TMPDIR/t3.jsonl"
DATA3="$TEST_TMPDIR/data3"
{
  failure_record "PreToolUse:OutOfWindow" "cmd-a"
  # Pad well past the small test cap so the record above falls outside it.
  for _ in $(seq 1 200); do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]},"uuid":"pad","session_id":"s"}\n' \
      "pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad"
  done
  failure_record "PreToolUse:InWindow" "cmd-b"
} >"$T3"
OUT6=$(run_hook "$T3" "$DATA3" HOOK_FAILURE_AUDIT_TAIL_BYTES=8000)
assert_contains "in-window failure reported" "$OUT6" "PreToolUse:InWindow"
assert_absent "out-of-window failure not read" "$OUT6" "PreToolUse:OutOfWindow"

# --- Kill switch -------------------------------------------------------------
OUT7=$(run_hook "$T2" "$TEST_TMPDIR/data-kill" CLAUDE_PLUGIN_OPTION_HOOK_FAILURE_AUDIT_ENABLED=false)
RC7=$?
assert_exit "kill switch -> exit 0" 0 "$RC7"
assert_silent "kill switch -> silent" "$OUT7"

# --- Missing / absent transcript: silent allow -------------------------------
OUT8=$(env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-miss" bash "$HOOK" <<<'{"session_id":"s","hook_event_name":"Stop"}' 2>&1)
RC8=$?
assert_exit "no transcript_path -> exit 0" 0 "$RC8"
assert_silent "no transcript_path -> silent" "$OUT8"
OUT9=$(env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-gone" bash "$HOOK" <<<"{\"session_id\":\"s\",\"transcript_path\":\"$TEST_TMPDIR/nope.jsonl\",\"hook_event_name\":\"Stop\"}" 2>&1)
RC9=$?
assert_exit "nonexistent transcript -> exit 0" 0 "$RC9"
assert_silent "nonexistent transcript -> silent" "$OUT9"

# --- Clean transcript: silent ------------------------------------------------
T4="$TEST_TMPDIR/t4.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"all fine"}]},"uuid":"c","session_id":"s"}\n' >"$T4"
OUT10=$(run_hook "$T4" "$TEST_TMPDIR/data-clean")
RC10=$?
assert_exit "clean transcript -> exit 0" 0 "$RC10"
assert_silent "clean transcript -> silent" "$OUT10"

# --- Telemetry envelope when a sink is wired ---------------------------------
T5="$TEST_TMPDIR/t5.jsonl"
make_transcript "$T5"
TEL="$TEST_TMPDIR/tel.json"
SINK="$(make_sink "$TEL")"
env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-tel" HOOK_TELEMETRY_SINK="$SINK" \
  bash "$HOOK" <<<"{\"session_id\":\"tel-session\",\"transcript_path\":\"$T5\",\"hook_event_name\":\"Stop\"}" >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_eq "hook id" "hook-failure-audit" "$(jq -r '.hook' "$TEL")"
  assert_eq "hook_event" "Stop" "$(jq -r '.hook_event' "$TEL")"
  assert_eq "status" "error" "$(jq -r '.status' "$TEL")"
  assert_eq "subject is the hook name (privacy-safe)" "PreToolUse:Bash" "$(jq -r '.data.subjects[0]' "$TEL")"
  assert_eq "total failure count" "1" "$(jq -r '.data.total' "$TEL")"
else
  bad "no envelope written when sink wired"
fi

report
