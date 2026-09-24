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
# cannot touch, which is the misdiagnosis #2849 exists to fix.
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
  for _ in {1..200}; do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]},"uuid":"pad","session_id":"s"}\n' \
      "pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad"
  done
  failure_record "PreToolUse:InWindow" "cmd-b"
} >"$T3"
OUT6=$(run_hook "$T3" "$DATA3" HOOK_FAILURE_AUDIT_TAIL_BYTES=8000)
assert_contains "in-window failure reported" "$OUT6" "PreToolUse:InWindow"
assert_absent "out-of-window failure not read" "$OUT6" "PreToolUse:OutOfWindow"

# --- Incremental scan: the cursor --------------------------------------------
# The cursor records the byte offset a session has already audited, so a later
# Stop reads only what was appended. The properties asserted: a turn with no
# candidate spawns nothing but the one `tail` that reads the appended bytes, a
# failure appended past the cursor produces EXACTLY the message a full rescan
# produces, a record before the cursor is not read again, a partial final line
# is read again next Stop, and a shorter, replaced, or differently-pathed
# transcript, or a line-count cursor, resets the cursor rather than skipping
# lines that were never audited.

# A PATH shim that fails loudly instead of doing the work. `command -v jq` still
# succeeds — that is what lets the library's builtin field parser proceed — so
# any surviving spawn reaches a shim and breaks silence. `tail` is left real:
# it is the warm read itself.
SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
for PROG in jq grep wc sed find cat mkdir; do
  printf '#!/bin/sh\necho "SPAWNED %s" >&2\nexit 99\n' "$PROG" >"$SHIM/$PROG"
  chmod +x "$SHIM/$PROG"
done
cursor_of() { head -1 "$1/hook-failure-audit/test-session.cursor"; } # <data_dir>
size_of() { wc -c <"$1" | tr -d ' '; }                               # <file>
benign_line() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"fine ✓"}]},"uuid":"c","session_id":"s"}\n'; }

T_CUR="$TEST_TMPDIR/cursor.jsonl"
DATA_CUR="$TEST_TMPDIR/data-cursor"
{
  for _ in {1..6}; do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"fine"}]},"uuid":"c","session_id":"s"}\n'
  done
  failure_record "PreToolUse:Bash" "first-registration.sh"
} >"$T_CUR"
OUT_C1=$(run_hook "$T_CUR" "$DATA_CUR")
assert_contains "cursor: first Stop warns" "$OUT_C1" "first-registration.sh"
assert_eq "cursor: file records the audited byte offset" "b$(size_of "$T_CUR")" \
  "$(cursor_of "$DATA_CUR")"
assert_eq "cursor: file records the transcript path" "$T_CUR" \
  "$(sed -n 2p "$DATA_CUR/hook-failure-audit/test-session.cursor")"

# Nothing appended: the second Stop must reach its exit with no process but tail.
OUT_C2=$(run_hook "$T_CUR" "$DATA_CUR" PATH="$SHIM:$PATH")
assert_silent "cursor: unchanged transcript -> silent, only tail spawned" "$OUT_C2"
assert_eq "cursor: unchanged transcript keeps the offset" "b$(size_of "$T_CUR")" "$(cursor_of "$DATA_CUR")"

# Benign lines only: still nothing to hand to jq, still only tail. Every line
# but the final one is counted; the final one is read again next Stop. The run
# uses a UTF-8 locale and benign_line carries a multibyte character, so an
# offset counted in characters instead of bytes lands short here.
for _ in {1..20}; do
  benign_line >>"$T_CUR"
done
OUT_C3=$(run_hook "$T_CUR" "$DATA_CUR" PATH="$SHIM:$PATH" LC_ALL=C.UTF-8)
assert_silent "cursor: appended benign lines -> silent, only tail spawned" "$OUT_C3"
assert_eq "cursor: advances to the start of the final line" \
  "b$(($(size_of "$T_CUR") - $(benign_line | wc -c)))" "$(cursor_of "$DATA_CUR")"

# A failure appended past the cursor: byte-identical to what a full rescan of
# the same transcript, against the same marker state, produces. DATA_FULL is a
# copy of the incremental state with only the cursor removed, so the two runs
# differ in nothing but how much of the transcript they read.
failure_record "SessionStart" "second-registration.mjs" >>"$T_CUR"
DATA_FULL="$TEST_TMPDIR/data-cursor-full"
rm -rf "$DATA_FULL"
cp -r "$DATA_CUR" "$DATA_FULL"
rm -f "$DATA_FULL/hook-failure-audit/test-session.cursor"
OUT_INC=$(run_hook "$T_CUR" "$DATA_CUR")
OUT_FULL=$(run_hook "$T_CUR" "$DATA_FULL")
assert_contains "cursor: appended failure is reported" "$OUT_INC" "second-registration.mjs"
assert_eq "cursor: incremental output equals a full rescan's" "$OUT_FULL" "$OUT_INC"
assert_absent "cursor: the already-warned registration stays muted" "$OUT_INC" "first-registration.sh"

# Only bytes past the cursor are read. The record BEFORE the cursor was never
# warned (no marker), so a read that reached it would name it.
T_SKIP="$TEST_TMPDIR/cursor-skip.jsonl"
DATA_SKIP="$TEST_TMPDIR/data-cursor-skip"
{
  failure_record "PreToolUse:Before" "before-cursor.sh"
  benign_line
} >"$T_SKIP"
mkdir -p "$DATA_SKIP/hook-failure-audit"
printf 'b%s\n%s\n' "$(size_of "$T_SKIP")" "$T_SKIP" >"$DATA_SKIP/hook-failure-audit/test-session.cursor"
failure_record "PreToolUse:After" "after-cursor.sh" >>"$T_SKIP"
benign_line >>"$T_SKIP"
OUT_SKIP=$(run_hook "$T_SKIP" "$DATA_SKIP")
assert_contains "cursor: a record past the cursor is reported" "$OUT_SKIP" "after-cursor.sh"
assert_absent "cursor: a record before the cursor is not read" "$OUT_SKIP" "before-cursor.sh"
OUT_SKIP2=$(run_hook "$T_SKIP" "$DATA_SKIP")
assert_silent "cursor: the next Stop does not report it again" "$OUT_SKIP2"

# A partial final line is read again once the harness finishes writing it.
T_PART="$TEST_TMPDIR/cursor-partial.jsonl"
DATA_PART="$TEST_TMPDIR/data-cursor-partial"
benign_line >"$T_PART"
run_hook "$T_PART" "$DATA_PART" >/dev/null
PART_RECORD=$(failure_record "PreToolUse:Partial" "partial-line.sh")
BEFORE_PART=$(size_of "$T_PART")
printf '%s' "${PART_RECORD:0:100}" >>"$T_PART"
OUT_P1=$(run_hook "$T_PART" "$DATA_PART")
assert_silent "cursor: a half-written record is not reported" "$OUT_P1"
assert_eq "cursor: a partial final line is not counted" "b$BEFORE_PART" "$(cursor_of "$DATA_PART")"
printf '%s\n' "${PART_RECORD:100}" >>"$T_PART"
OUT_P2=$(run_hook "$T_PART" "$DATA_PART")
assert_contains "cursor: the completed line is read again and reported" "$OUT_P2" "partial-line.sh"

# A SHORTER transcript resets the cursor. Without the reset the read starts past
# the end of the file and the new record is never seen.
T_SHORT="$TEST_TMPDIR/cursor.jsonl"
failure_record "PreToolUse:Shrunk" "after-truncation.sh" >"$T_SHORT"
OUT_C4=$(run_hook "$T_SHORT" "$DATA_CUR")
assert_contains "cursor: a shorter transcript rescans from the start" "$OUT_C4" "after-truncation.sh"

# A DIFFERENT transcript_path resets it too. This file is LONGER than the stored
# cursor and carries its failure record BEFORE it, so only the path check can
# save the record: a stale line count would skip straight past it.
T_OTHER="$TEST_TMPDIR/cursor-other.jsonl"
DATA_OTHER="$TEST_TMPDIR/data-cursor-other"
{
  for _ in {1..30}; do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"fine"}]},"uuid":"c","session_id":"s"}\n'
  done
} >"$T_OTHER"
run_hook "$T_OTHER" "$DATA_OTHER" >/dev/null # cursor: 30 lines of this path
printf '%s\n' "$(failure_record 'PreToolUse:Moved' 'other-transcript.sh')" \
  >"$TEST_TMPDIR/cursor-other-2.jsonl"
for _ in {1..40}; do
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"fine"}]},"uuid":"c","session_id":"s"}\n' >>"$TEST_TMPDIR/cursor-other-2.jsonl"
done
OUT_C5=$(run_hook "$TEST_TMPDIR/cursor-other-2.jsonl" "$DATA_OTHER")
assert_contains "cursor: a different transcript_path rescans from the start" \
  "$OUT_C5" "other-transcript.sh"

# A file REPLACED at the same path by a longer one: enough bytes, but no line
# boundary where the cursor points, so the anchor check resets the cursor and
# the record before the old offset is still found.
T_REPL="$TEST_TMPDIR/cursor-replaced.jsonl"
DATA_REPL="$TEST_TMPDIR/data-cursor-replaced"
for _ in {1..10}; do benign_line; done >"$T_REPL"
run_hook "$T_REPL" "$DATA_REPL" >/dev/null
{
  failure_record "PreToolUse:Replaced" "replaced-transcript.sh"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$(printf 'x%.0s' {1..3000})"
} >"$T_REPL"
OUT_REPL=$(run_hook "$T_REPL" "$DATA_REPL")
assert_contains "cursor: a replaced transcript rescans from the start" "$OUT_REPL" "replaced-transcript.sh"

# A line-count cursor from before the byte offset: no `b` prefix, so it reads as
# malformed and takes the cold path. The registration it already warned about
# stays muted by its marker; the one appended since is reported once.
T_LEGACY="$TEST_TMPDIR/cursor-legacy.jsonl"
DATA_LEGACY="$TEST_TMPDIR/data-cursor-legacy"
{
  failure_record "PreToolUse:Legacy" "legacy-warned.sh"
  benign_line
} >"$T_LEGACY"
run_hook "$T_LEGACY" "$DATA_LEGACY" >/dev/null
printf '2\n%s\n' "$T_LEGACY" >"$DATA_LEGACY/hook-failure-audit/test-session.cursor"
failure_record "PreToolUse:Legacy" "legacy-new.sh" >>"$T_LEGACY"
benign_line >>"$T_LEGACY"
OUT_L1=$(run_hook "$T_LEGACY" "$DATA_LEGACY")
assert_contains "cursor: a line-count cursor still reports what followed it" "$OUT_L1" "legacy-new.sh"
assert_absent "cursor: a line-count cursor does not re-warn" "$OUT_L1" "legacy-warned.sh"
assert_eq "cursor: a line-count cursor is rewritten as a byte offset" \
  "b$(size_of "$T_LEGACY")" "$(cursor_of "$DATA_LEGACY")"
OUT_L2=$(run_hook "$T_LEGACY" "$DATA_LEGACY")
assert_silent "cursor: the migrated cursor does not report again" "$OUT_L2"

# A non-canonical decimal cursor (a leading zero, or a digit string long enough
# to wrap) must fall through to CURSOR=0 exactly like any other malformed
# cursor: no shell diagnostic, a cold scan of the whole transcript, and a
# canonical value written back afterward. `08`/`09` pass a bare `^[0-9]+$`
# test and then fail bash's octal-reading `((...))` with a "value too great
# for base" diagnostic on stderr; a long-enough digit string wraps silently in
# arithmetic instead of erroring, which is the more dangerous case.
T_LEADING_ZERO="$TEST_TMPDIR/cursor-leading-zero.jsonl"
DATA_LEADING_ZERO="$TEST_TMPDIR/data-cursor-leading-zero"
failure_record "PreToolUse:LeadingZero" "leading-zero.sh" >"$T_LEADING_ZERO"
mkdir -p "$DATA_LEADING_ZERO/hook-failure-audit"
printf 'b08\n%s\n' "$T_LEADING_ZERO" \
  >"$DATA_LEADING_ZERO/hook-failure-audit/test-session.cursor"
OUT_C6=$(run_hook "$T_LEADING_ZERO" "$DATA_LEADING_ZERO")
assert_absent "cursor: leading zero prints no shell diagnostic" "$OUT_C6" "value too great for base"
assert_contains "cursor: leading zero falls back to a cold scan" "$OUT_C6" "leading-zero.sh"
assert_eq "cursor: leading zero is rewritten to a canonical value" "b$(size_of "$T_LEADING_ZERO")" \
  "$(cursor_of "$DATA_LEADING_ZERO")"

T_OVERSIZED="$TEST_TMPDIR/cursor-oversized.jsonl"
DATA_OVERSIZED="$TEST_TMPDIR/data-cursor-oversized"
failure_record "PreToolUse:Oversized" "oversized-cursor.sh" >"$T_OVERSIZED"
mkdir -p "$DATA_OVERSIZED/hook-failure-audit"
printf 'b%s\n%s\n' "11111111111111111111" "$T_OVERSIZED" \
  >"$DATA_OVERSIZED/hook-failure-audit/test-session.cursor"
OUT_C7=$(run_hook "$T_OVERSIZED" "$DATA_OVERSIZED")
# bash wraps an overlong digit string silently rather than erroring, so the
# diagnostic to rule out here is any stray output line, not one exact string.
if [[ "$OUT_C7" == *$'\n'* ]]; then
  bad "cursor: 20-digit cursor prints no shell diagnostic: unexpected extra line(s) in: $OUT_C7"
else
  ok "cursor: 20-digit cursor prints no shell diagnostic"
fi
assert_contains "cursor: 20-digit cursor falls back to a cold scan" "$OUT_C7" "oversized-cursor.sh"
assert_eq "cursor: 20-digit cursor is rewritten to a canonical value" "b$(size_of "$T_OVERSIZED")" \
  "$(cursor_of "$DATA_OVERSIZED")"

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

# --- Spawn budget on the common path (strace, not xtrace) --------------------
# This hook runs on EVERY Stop, and `docs/conventions/hook-budget/README.md`
# states each always-on hook's budget in process spawns (k x S), not
# milliseconds. On the host in #3508 one process creation costs 180-2,841 ms,
# so the budget here is a PROCESS COUNT, not a duration: durations on that host
# are not comparable across time, and wall clock on a Linux runner says nothing
# about the Windows spawn tax.
#
# Counted with strace, NOT with `bash -x`. Shard #3520 established that xtrace
# undercounts badly — it reads command POSITIONS, and bash forks a subshell for
# a command substitution ON TOP OF the exec inside it whenever the substituted
# command carries a redirection of its own. Those forks are invisible to xtrace
# and are the whole cost this budget guards.
#
# `-ff` writes one file per pid, so no syscall line is ever split across an
# <unfinished>/<resumed> pair where a naive grep would silently undercount.
#
# TWO paths are measured, because the cursor splits them. The COLD path is the
# first Stop of a session, under the tail cap:
#   1 wc     `wc -c`: the byte count the cap decision needs and the offset the
#            cursor starts from, in one process
#   1 mkdir  the marker/cursor directory, created once per data home
#   0 jq     the payload fields ride on hook::buffer_stdin_to, and the library
#            answers a plain-string field with its builtin parser
#   0 grep   the pre-filter is `[[ $line == *needle* ]]` over a `mapfile` read
#   0 cat, 0 tail, 0 sed
# The WARM path — every later Stop, which is the cadence this hook actually runs
# at — creates ONE process, the `tail` that reads the bytes past the cursor.
#
# MUTATION-CHECKED: moving a silenced redirect back inside its substitution
# (`SIZE=$(wc -c <"$TRANSCRIPT" 2>/dev/null)`) adds a fork with NO new exec,
# leaves every behavioral assertion above green, and trips the cold creation
# ceiling below. Dropping the cursor write sends every Stop down the cold path
# instead, which trips the one-tail assertion on the warm trace.
TRACE_OK=1
command -v strace >/dev/null 2>&1 || TRACE_OK=0
if ((TRACE_OK)); then
  strace -ff -qq -e trace=execve -o "$TEST_TMPDIR/probe" true >/dev/null 2>&1 || TRACE_OK=0
fi
if ((TRACE_OK == 0)); then
  echo "skip: strace unavailable or not permitted here — spawn budget not measured"
else
  TB="$TEST_TMPDIR/budget.jsonl"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"all fine"}]},"uuid":"c","session_id":"s"}\n' >"$TB"
  TRACE_ALL=""
  trace_hook() { # <trace-name>
    local prefix="$TEST_TMPDIR/$1"
    env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-budget" HOOK_TELEMETRY_SINK="" \
      strace -ff -qq -s 400 -e trace=clone,clone3,fork,vfork,execve -o "$prefix" \
      bash "$HOOK" <<<"{\"session_id\":\"budget\",\"transcript_path\":\"$TB\",\"hook_event_name\":\"Stop\"}" \
      >/dev/null 2>&1
    TRACE_ALL="$prefix.all"
    cat "$prefix".* >"$TRACE_ALL" 2>/dev/null
  }
  # Every process creation the kernel saw, subshell forks included.
  creations() { grep -cE '^(clone|clone3|fork|vfork)\(' "$TRACE_ALL"; }
  # Successful execs only: a PATH search emits failing execve calls that spawn
  # nothing. The `bash <hook>` exec at the top is strace's own, not a cost of
  # the hook, and is excluded by matching the hook path in its argv — which is
  # why the trace runs with `-s 400`: at strace's 32-byte default that path is
  # abbreviated and the exclusion silently matches nothing.
  execs() { grep -E '^execve\(.*= 0$' "$TRACE_ALL" | grep -c -v -e "$HOOK"; }
  progs() {
    grep -E '^execve\(.*= 0$' "$TRACE_ALL" | grep -v -e "$HOOK" |
      grep -oE '^execve\("[^"]+"' | sed 's|.*/||; s|"||' | sort | uniq -c | tr -s ' \n' ' '
  }
  prog_count() { grep -cE "^execve\\(\"[^\"]*/$1\"" "$TRACE_ALL"; }
  ceiling() { # <label> <actual> <max>
    if (($2 <= $3)); then ok "budget: $1 is $2 (ceiling $3)"; else bad "budget: $1 is $2, ceiling is $3 —$(progs)"; fi
  }

  trace_hook budget-cold
  if [[ -s "$TRACE_ALL" ]]; then
    ok "budget: the cold path was traced"
  else
    bad "budget: no usable strace output captured"
  fi
  ceiling "cold path creations" "$(creations)" 6
  ceiling "cold path execs" "$(execs)" 2
  assert_eq "budget: no grep pre-filter on the cold path" 0 "$(prog_count grep)"
  assert_eq "budget: no cat feeding the pre-filter" 0 "$(prog_count cat)"
  assert_eq "budget: no jq for the payload fields" 0 "$(prog_count jq)"
  assert_eq "budget: one wc for the cap decision and the cursor" 1 "$(prog_count wc)"

  # The same Stop again, now with a cursor: one read of the bytes past it.
  trace_hook budget-warm
  ceiling "warm path creations" "$(creations)" 1
  ceiling "warm path execs" "$(execs)" 1
  assert_eq "budget: the warm read is one tail" 1 "$(prog_count tail)"
fi

report
