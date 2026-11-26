#!/usr/bin/env bash
# test-scope: plugins/plugin-diagnostics/hooks/hooks.json
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/hook-failure-audit.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=plugin-diagnostics-test-helpers.sh
source "$HOOK_DIR/plugin-diagnostics-test-helpers.sh"
unset CLAUDE_PROJECT_DIR

WSL_STDERR='Failed with non-blocking status code: <3>WSL (10 - Relay) ERROR: CreateProcessCommon:818: execvpe(/bin/bash) failed: No such file or directory'

failure_record() {
  printf '{"parentUuid":"p","isSidechain":false,"attachment":{"type":"hook_non_blocking_error","hookName":"%s","toolUseID":"toolu_x","hookEvent":"PreToolUse","stderr":"%s","stdout":"","exitCode":1,"command":"%s","durationMs":2080},"type":"attachment","uuid":"u","timestamp":"2026-08-13T13:56:38.155Z","session_id":"s","sessionId":"s","version":"2.1.228"}\n' \
    "$1" "${WSL_STDERR//\"/\\\"}" "$2"
}

make_transcript() {
  local t="$1"
  {
    printf 'garbage-not-json {"half": \n'
    failure_record "PreToolUse:Bash" "bash \${CLAUDE_PLUGIN_ROOT}/hooks/run-python-hook.sh"
    printf '{"attachment":{"type":"hook_success","hookName":"PostToolUse:Edit","stdout":"saw hook_non_blocking_error and %s in a log","stderr":"","exitCode":0},"type":"attachment","uuid":"u2","session_id":"s"}\n' "${WSL_STDERR//\"/\\\"}"
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"sample: {\\"type\\": \\"hook_non_blocking_error\\", \\"hookName\\": \\"PreToolUse:QuotedOnly\\"}"}]},"uuid":"u3","session_id":"s"}\n'
  } >"$t"
}

run_hook() {
  local transcript="$1" data_dir="$2"
  shift 2
  env CLAUDE_PLUGIN_DATA="$data_dir" "$@" "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$transcript\",\"hook_event_name\":\"Stop\"}" 2>&1
}

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
assert_contains "stale-session guidance names /reload-plugins before restart" "$OUT" \
  "Run /reload-plugins to load the current config, or restart the session."

NOJQ_BIN="$TEST_TMPDIR/nojq-bin"
mkdir -p "$NOJQ_BIN" "$TEST_TMPDIR/data-nojq/skip-notices"
for t in bash cat env mkdir find tr grep sed uname date; do
  real_t="$(command -v "$t" 2>/dev/null)" && ln -s "$real_t" "$NOJQ_BIN/$t"
done
OUT_NOJQ=$(PATH="$NOJQ_BIN" run_hook "$T1" "$TEST_TMPDIR/data-nojq")
assert_contains "no jq -> user notice" "$OUT_NOJQ" "systemMessage"
assert_absent "no jq -> nothing for the model on Stop" "$OUT_NOJQ" "additionalContext"

assert_absent "hook_success quoting an error does not fire" "$OUT" "PostToolUse:Edit"
assert_absent "string-quoted record does not fire" "$OUT" "PreToolUse:QuotedOnly"

OUT2=$(run_hook "$T1" "$DATA1")
RC2=$?
assert_exit "dedup run -> exit 0" 0 "$RC2"
assert_silent "same failures already warned -> silent" "$OUT2"

failure_record "SessionStart" "node missing-lifecycle-hook.mjs" >>"$T1"
OUT3=$(run_hook "$T1" "$DATA1")
assert_contains "new failing hook warned" "$OUT3" "SessionStart"
assert_absent "already-warned hook muted" "$OUT3" "PreToolUse:Bash"

failure_record "PreToolUse:Bash" "other-plugin-guard.sh --different-registration" >>"$T1"
OUT3B=$(run_hook "$T1" "$DATA1")
assert_contains "same hookName, new registration -> re-warns" "$OUT3B" "other-plugin-guard.sh"
OUT3C=$(run_hook "$T1" "$DATA1")
assert_silent "both registrations warned -> silent" "$OUT3C"

T2="$TEST_TMPDIR/t2.jsonl"
make_transcript "$T2"
OUT4=$(env -u CLAUDE_PLUGIN_DATA bash "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$T2\",\"hook_event_name\":\"Stop\"}" 2>&1)
assert_contains "no marker home -> still warns" "$OUT4" "PreToolUse:Bash"
OUT5=$(env -u CLAUDE_PLUGIN_DATA bash "$HOOK" <<<"{\"session_id\":\"test-session\",\"transcript_path\":\"$T2\",\"hook_event_name\":\"Stop\"}" 2>&1)
assert_contains "no marker home -> re-warns rather than suppresses" "$OUT5" "PreToolUse:Bash"

HARNESS_NO_STDERR='Failed with non-blocking status code: No stderr output'

custom_record() {
  printf '{"parentUuid":"p","isSidechain":false,"attachment":{"type":"hook_non_blocking_error","hookName":"%s","toolUseID":"toolu_x","hookEvent":"Stop","stderr":"%s","stdout":"","exitCode":%s,"command":"%s","durationMs":%s},"type":"attachment","uuid":"u","timestamp":"2026-08-13T13:56:38.155Z","session_id":"s","sessionId":"s","version":"2.1.228"}\n' \
    "$1" "${3//\"/\\\"}" "$4" "$2" "$5"
}

T_DONE="$TEST_TMPDIR/completed.jsonl"
custom_record "Stop:ran-and-failed" "node stop-hook.mjs" "$HARNESS_NO_STDERR" 1 1190 >"$T_DONE"
OUT_DONE=$(run_hook "$T_DONE" "$TEST_TMPDIR/data-done")
RC_DONE=$?
assert_exit "completed non-zero exit -> exit 0" 0 "$RC_DONE"
assert_contains "completed record is still surfaced" "$OUT_DONE" "Stop:ran-and-failed"
assert_contains "diagnosed as a completed non-zero exit" "$OUT_DONE" "completed non-zero exit"
assert_absent "not described as a launch failure" "$OUT_DONE" "fails to launch"
assert_absent "no restart-the-session remedy" "$OUT_DONE" "restart"
assert_absent "no reload remedy for a hook that ran" "$OUT_DONE" "/reload-plugins"
assert_absent "harness placeholder not attributed to the hook" "$OUT_DONE" "$HARNESS_NO_STDERR"
assert_contains "no-stderr rendered as an explicit marker" "$OUT_DONE" "last stderr: (none — hook produced no stderr)"

REAL_STDERR='TypeError: Cannot read properties of undefined (reading cwd) at hooks/broken-stop.mjs:42:11'
T_REAL="$TEST_TMPDIR/real-stderr.jsonl"
custom_record "Stop:threw" "node broken-stop.mjs" "$REAL_STDERR" 1 640 >"$T_REAL"
OUT_REAL=$(run_hook "$T_REAL" "$TEST_TMPDIR/data-real")
assert_contains "real stderr passed through unchanged" "$OUT_REAL" "$REAL_STDERR"
assert_absent "real stderr not replaced by the no-output marker" "$OUT_REAL" "hook produced no stderr"
assert_absent "a hook that ran and threw is not a launch failure" "$OUT_REAL" "fails to launch"

T_EXECVPE="$TEST_TMPDIR/execvpe.jsonl"
custom_record "PreToolUse:Bash" "bash relay-guard.sh" "$WSL_STDERR" 1 8 >"$T_EXECVPE"
OUT_EXECVPE=$(run_hook "$T_EXECVPE" "$TEST_TMPDIR/data-execvpe")
assert_contains "execvpe at exit 1 is still a launch failure" "$OUT_EXECVPE" "launch failure"
assert_contains "execvpe keeps the fails-to-launch wording" "$OUT_EXECVPE" "fails to launch"
assert_contains "execvpe keeps the restart remedy" "$OUT_EXECVPE" "restart"
assert_absent "execvpe at exit 1 is not called ambiguous" "$OUT_EXECVPE" "ambiguous"

T_NOTFOUND="$TEST_TMPDIR/notfound.jsonl"
# shellcheck disable=SC2016 # literal $PATH and ${CLAUDE_PROJECT_DIR} must not expand
custom_record "PreToolUse:Bash" 'node ${CLAUDE_PROJECT_DIR}/probe-hook.mjs' \
  'Failed with non-blocking status code: Error occurred while executing hook command: Executable not found in $PATH: "node"' 1 8 >"$T_NOTFOUND"
OUT_NOTFOUND=$(run_hook "$T_NOTFOUND" "$TEST_TMPDIR/data-notfound")
assert_contains "missing executable at exit 1 is a launch failure" "$OUT_NOTFOUND" "launch failure"
assert_contains "missing executable uses the fails-to-launch wording" "$OUT_NOTFOUND" "fails to launch"
assert_absent "missing executable is not a completed non-zero exit" "$OUT_NOTFOUND" "completed non-zero exit"
assert_absent "missing executable is not called ambiguous" "$OUT_NOTFOUND" "ambiguous"

T_RELAY="$TEST_TMPDIR/relay.jsonl"
# shellcheck disable=SC2016 # literal $PATH must not expand
custom_record "PreToolUse:Bash" 'bash ${CLAUDE_PROJECT_DIR}/wrapper.sh' \
  'wrapper: Executable not found in $PATH: "jq"' 1 8 >"$T_RELAY"
OUT_RELAY=$(run_hook "$T_RELAY" "$TEST_TMPDIR/data-relay")
assert_absent "a relayed phrase without the launcher prefix is not a launch failure" "$OUT_RELAY" "launch failure"

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

T_127="$TEST_TMPDIR/exit127.jsonl"
custom_record "PreToolUse:Bash" "missing-binary --guard" "$HARNESS_NO_STDERR" 127 12 >"$T_127"
OUT_127=$(run_hook "$T_127" "$TEST_TMPDIR/data-127")
assert_contains "bare exit 127 is reported ambiguous" "$OUT_127" \
  "ambiguous: exit 126/127 with no exec-failure signature"
assert_contains "bare exit 127 says both readings are possible" "$OUT_127" "Both are possible"
assert_absent "bare exit 127 is not asserted to be a launch failure" "$OUT_127" "fails to launch"
assert_absent "bare exit 127 is not asserted to have completed" "$OUT_127" "no exec-failure evidence"
assert_contains "bare exit 127 still offers the restart remedy" "$OUT_127" "restart"
assert_contains "bare exit 127 names /reload-plugins first" "$OUT_127" "Run /reload-plugins"
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

STALE_LABEL="stale config: registered script missing from disk"
STATUS_MSG="Checking the context-zone gate..."
PFX="Failed with non-blocking status code: "
stale_case() {
  local t="$TEST_TMPDIR/stale-$1.jsonl"
  custom_record "PreToolUse:Edit" "$2" "$3" 127 40 >"$t"
  run_hook "$t" "$TEST_TMPDIR/data-stale-$1"
}
assert_stale() {
  assert_contains "$1: classed stale config" "$2" "$STALE_LABEL"
  assert_contains "$1: names /reload-plugins before restart" "$2" \
    "Run /reload-plugins to load the current config, or restart the session."
  assert_contains "$1: says the guard enforced nothing" "$2" "enforced nothing for the calls listed"
  assert_absent "$1: not called ambiguous" "$2" "ambiguous"
  assert_absent "$1: no false lead into the hook's own logic" "$2" "read the hook's own logic"
  assert_absent "$1: remedy given once, not twice" "$2" "If a plugin update"
}
OUT_S=$(stale_case observed-mixed "$STATUS_MSG" \
  "${PFX}/usr/bin/bash: C:\\\\code\\\\melodic\\\\claude-code-plugins\\\\plugins\\\\context-usage/hooks/zone-gate.sh: No such file or directory")
assert_stale "observed mixed separators" "$OUT_S"
OUT_S=$(stale_case observed-forward "Checking the ready-for-review flip against the mandatory pre-PR skill evidence..." \
  "${PFX}bash: C:/code/melodic/claude-code-plugins/plugins/source-control/hooks/pr-ready-evidence-gate.sh: No such file or directory")
assert_stale "observed forward-slash drive" "$OUT_S"
OUT_S=$(stale_case backslash "$STATUS_MSG" \
  "${PFX}bash: C:\\\\code\\\\plugins\\\\context-usage\\\\hooks\\\\zone-gate.sh: No such file or directory")
assert_stale "backslash-only Windows path" "$OUT_S"
OUT_S=$(stale_case msys "$STATUS_MSG" \
  "${PFX}/usr/bin/bash: /c/code/plugins/context-usage/hooks/zone-gate.sh: No such file or directory")
assert_stale "MSYS /c/ path" "$OUT_S"
# shellcheck disable=SC2016 # literal ${CLAUDE_PLUGIN_ROOT} must not expand
OUT_S=$(stale_case literal-root 'node ${CLAUDE_PLUGIN_ROOT}/hooks/exec-bash.mjs ${CLAUDE_PLUGIN_ROOT}/hooks/zone-gate.sh' \
  "${PFX}/usr/bin/bash: C:\\\\code\\\\plugins\\\\context-usage/hooks/zone-gate.sh: No such file or directory")
assert_stale "command with literal CLAUDE_PLUGIN_ROOT" "$OUT_S"
OUT_S=$(stale_case expanded-root 'node C:\\code\\plugins\\context-usage\\hooks\\exec-bash.mjs C:\\code\\plugins\\context-usage\\hooks\\zone-gate.sh' \
  "${PFX}/usr/bin/bash: /c/code/plugins/context-usage/hooks/zone-gate.sh: No such file or directory")
assert_stale "command with CLAUDE_PLUGIN_ROOT expanded" "$OUT_S"

OUT_S=$(stale_case in-script "$STATUS_MSG" \
  "${PFX}/c/code/plugins/x/hooks/my-hook.sh: line 12: /c/code/plugins/x/hooks/child.sh: No such file or directory")
assert_contains "missing child inside a running hook stays ambiguous" "$OUT_S" \
  "ambiguous: exit 126/127 with no exec-failure signature"
assert_absent "missing child inside a running hook is not stale config" "$OUT_S" "$STALE_LABEL"
OUT_S=$(stale_case bash-c-line "$STATUS_MSG" "${PFX}bash: line 1: helper.sh: No such file or directory")
assert_absent "bash -c line-numbered error is not stale config" "$OUT_S" "$STALE_LABEL"
# shellcheck disable=SC2016 # literal ${CLAUDE_PLUGIN_ROOT} must not expand
OUT_S=$(stale_case other-basename 'bash ${CLAUDE_PLUGIN_ROOT}/hooks/wrapper.sh' \
  "${PFX}bash: C:/code/plugins/x/hooks/child-helper.sh: No such file or directory")
assert_contains "missing path not in the registered command stays ambiguous" "$OUT_S" \
  "ambiguous: exit 126/127 with no exec-failure signature"
assert_absent "missing path not in the registered command is not stale config" "$OUT_S" "$STALE_LABEL"
T_S1="$TEST_TMPDIR/stale-exit1.jsonl"
custom_record "PreToolUse:Edit" "$STATUS_MSG" \
  "${PFX}bash: C:/code/plugins/x/hooks/zone-gate.sh: No such file or directory" 1 40 >"$T_S1"
OUT_S=$(run_hook "$T_S1" "$TEST_TMPDIR/data-stale-exit1")
assert_contains "missing-operand line at exit 1 stays completed" "$OUT_S" "completed non-zero exit"
assert_absent "missing-operand line at exit 1 is not stale config" "$OUT_S" "$STALE_LABEL"

T_SUBCMD="$TEST_TMPDIR/missing-subcommand.jsonl"
custom_record "Stop:lint" "bash lint-stop.sh" \
  "'ripgrep' is not recognized as an internal or external command, operable program or batch file." \
  1 800 >"$T_SUBCMD"
OUT_SUBCMD=$(run_hook "$T_SUBCMD" "$TEST_TMPDIR/data-subcmd")
assert_contains "missing subcommand is a completed non-zero exit" "$OUT_SUBCMD" "completed non-zero exit"
assert_absent "missing subcommand is not a launch failure" "$OUT_SUBCMD" "fails to launch"
assert_absent "missing subcommand gets no restart remedy" "$OUT_SUBCMD" "restart"

T_NOEC="$TEST_TMPDIR/no-exitcode.jsonl"
printf '{"attachment":{"type":"hook_non_blocking_error","hookName":"Stop:noexit","stderr":"something went wrong","stdout":"","command":"bash mystery.sh","durationMs":50},"type":"attachment","uuid":"u","session_id":"s"}\n' >"$T_NOEC"
OUT_NOEC=$(run_hook "$T_NOEC" "$TEST_TMPDIR/data-noec")
assert_contains "absent exitCode still surfaced" "$OUT_NOEC" "Stop:noexit"
assert_contains "absent exitCode renders as unknown" "$OUT_NOEC" "exit ?"
assert_absent "absent exitCode is not asserted to have launched" "$OUT_NOEC" "it did launch"

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

assert_absent "no maintainer-facing implementation prose" "$OUT_EXECVPE" "empty-stderr placeholder"
assert_absent "no maintainer-facing implementation prose (completed)" "$OUT_DONE" "empty-stderr placeholder"

T3="$TEST_TMPDIR/t3.jsonl"
DATA3="$TEST_TMPDIR/data3"
{
  failure_record "PreToolUse:OutOfWindow" "cmd-a"
  for _ in {1..200}; do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]},"uuid":"pad","session_id":"s"}\n' \
      "pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad-pad"
  done
  failure_record "PreToolUse:InWindow" "cmd-b"
} >"$T3"
OUT6=$(run_hook "$T3" "$DATA3" HOOK_FAILURE_AUDIT_TAIL_BYTES=8000)
assert_contains "in-window failure reported" "$OUT6" "PreToolUse:InWindow"
assert_absent "out-of-window failure not read" "$OUT6" "PreToolUse:OutOfWindow"


SHIM="$TEST_TMPDIR/shim"
mkdir -p "$SHIM"
for PROG in jq grep wc sed find cat mkdir; do
  printf '#!/bin/sh\necho "SPAWNED %s" >&2\nexit 99\n' "$PROG" >"$SHIM/$PROG"
  chmod +x "$SHIM/$PROG"
done
cursor_of() { head -1 "$1/hook-failure-audit/test-session.cursor"; }
size_of() { wc -c <"$1" | tr -d ' '; }
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

OUT_C2=$(run_hook "$T_CUR" "$DATA_CUR" PATH="$SHIM:$PATH")
assert_silent "cursor: unchanged transcript -> silent, only tail spawned" "$OUT_C2"
assert_eq "cursor: unchanged transcript keeps the offset" "b$(size_of "$T_CUR")" "$(cursor_of "$DATA_CUR")"

for _ in {1..20}; do
  benign_line >>"$T_CUR"
done
OUT_C3=$(run_hook "$T_CUR" "$DATA_CUR" PATH="$SHIM:$PATH" LC_ALL=C.UTF-8)
assert_silent "cursor: appended benign lines -> silent, only tail spawned" "$OUT_C3"
assert_eq "cursor: advances to the start of the final line" \
  "b$(($(size_of "$T_CUR") - $(benign_line | wc -c)))" "$(cursor_of "$DATA_CUR")"

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

T_SHORT="$TEST_TMPDIR/cursor.jsonl"
failure_record "PreToolUse:Shrunk" "after-truncation.sh" >"$T_SHORT"
OUT_C4=$(run_hook "$T_SHORT" "$DATA_CUR")
assert_contains "cursor: a shorter transcript rescans from the start" "$OUT_C4" "after-truncation.sh"

T_OTHER="$TEST_TMPDIR/cursor-other.jsonl"
DATA_OTHER="$TEST_TMPDIR/data-cursor-other"
{
  for _ in {1..30}; do
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"fine"}]},"uuid":"c","session_id":"s"}\n'
  done
} >"$T_OTHER"
run_hook "$T_OTHER" "$DATA_OTHER" >/dev/null
printf '%s\n' "$(failure_record 'PreToolUse:Moved' 'other-transcript.sh')" \
  >"$TEST_TMPDIR/cursor-other-2.jsonl"
for _ in {1..40}; do
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"fine"}]},"uuid":"c","session_id":"s"}\n' >>"$TEST_TMPDIR/cursor-other-2.jsonl"
done
OUT_C5=$(run_hook "$TEST_TMPDIR/cursor-other-2.jsonl" "$DATA_OTHER")
assert_contains "cursor: a different transcript_path rescans from the start" \
  "$OUT_C5" "other-transcript.sh"

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
if [[ "$OUT_C7" == *$'\n'* ]]; then
  bad "cursor: 20-digit cursor prints no shell diagnostic: unexpected extra line(s) in: $OUT_C7"
else
  ok "cursor: 20-digit cursor prints no shell diagnostic"
fi
assert_contains "cursor: 20-digit cursor falls back to a cold scan" "$OUT_C7" "oversized-cursor.sh"
assert_eq "cursor: 20-digit cursor is rewritten to a canonical value" "b$(size_of "$T_OVERSIZED")" \
  "$(cursor_of "$DATA_OVERSIZED")"

OUT7=$(run_hook "$T2" "$TEST_TMPDIR/data-kill" CLAUDE_PLUGIN_OPTION_HOOK_FAILURE_AUDIT_ENABLED=false)
RC7=$?
assert_exit "kill switch -> exit 0" 0 "$RC7"
assert_silent "kill switch -> silent" "$OUT7"

OUT8=$(env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-miss" bash "$HOOK" <<<'{"session_id":"s","hook_event_name":"Stop"}' 2>&1)
RC8=$?
assert_exit "no transcript_path -> exit 0" 0 "$RC8"
assert_silent "no transcript_path -> silent" "$OUT8"
OUT9=$(env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-gone" bash "$HOOK" <<<"{\"session_id\":\"s\",\"transcript_path\":\"$TEST_TMPDIR/nope.jsonl\",\"hook_event_name\":\"Stop\"}" 2>&1)
RC9=$?
assert_exit "nonexistent transcript -> exit 0" 0 "$RC9"
assert_silent "nonexistent transcript -> silent" "$OUT9"

T4="$TEST_TMPDIR/t4.jsonl"
printf '{"type":"assistant","message":{"content":[{"type":"text","text":"all fine"}]},"uuid":"c","session_id":"s"}\n' >"$T4"
OUT10=$(run_hook "$T4" "$TEST_TMPDIR/data-clean")
RC10=$?
assert_exit "clean transcript -> exit 0" 0 "$RC10"
assert_silent "clean transcript -> silent" "$OUT10"

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
  trace_hook() {
    local prefix="$TEST_TMPDIR/$1"
    env CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/data-budget" HOOK_TELEMETRY_SINK="" \
      strace -ff -qq -s 400 -e trace=clone,clone3,fork,vfork,execve -o "$prefix" \
      bash "$HOOK" <<<"{\"session_id\":\"budget\",\"transcript_path\":\"$TB\",\"hook_event_name\":\"Stop\"}" \
      >/dev/null 2>&1
    TRACE_ALL="$prefix.all"
    cat "$prefix".* >"$TRACE_ALL" 2>/dev/null
  }
  creations() { grep -cE '^(clone|clone3|fork|vfork)\(' "$TRACE_ALL"; }
  execs() { grep -E '^execve\(.*= 0$' "$TRACE_ALL" | grep -c -v -e "$HOOK"; }
  progs() {
    grep -E '^execve\(.*= 0$' "$TRACE_ALL" | grep -v -e "$HOOK" |
      grep -oE '^execve\("[^"]+"' | sed 's|.*/||; s|"||' | sort | uniq -c | tr -s ' \n' ' '
  }
  prog_count() { grep -cE "^execve\\(\"[^\"]*/$1\"" "$TRACE_ALL"; }
  ceiling() {
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

  trace_hook budget-warm
  ceiling "warm path creations" "$(creations)" 1
  ceiling "warm path execs" "$(execs)" 1
  assert_eq "budget: the warm read is one tail" 1 "$(prog_count tail)"
fi

: >"$TEST_TMPDIR/empty.err"
empty_rc=0
printf '' | bash "$HOOK" >/dev/null 2>"$TEST_TMPDIR/empty.err" || empty_rc=$?
assert_exit "empty stdin exits 0" 0 "$empty_rc"
mal_rc=0
printf 'not-json' | bash "$HOOK" >/dev/null 2>"$TEST_TMPDIR/mal.err" || mal_rc=$?
assert_exit "malformed JSON exits 0" 0 "$mal_rc"
min_rc=0
printf '%s' '{"session_id":"s","transcript_path":"/no/such.jsonl","hook_event_name":"Stop"}' \
  | bash "$HOOK" >/dev/null 2>"$TEST_TMPDIR/min.err" || min_rc=$?
assert_exit "minimal Stop payload with missing transcript exits 0" 0 "$min_rc"

HFA_COPY="$TEST_TMPDIR/hfa-abort.sh"
cp "$HOOK" "$HFA_COPY"
python3 - "$HFA_COPY" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
needle = "trap _hfa_on_exit EXIT\n"
if needle not in text:
    raise SystemExit("abort-boundary trap line missing")
p.write_text(text.replace(needle, needle + "exit 3\n", 1))
PY
abort_rc=0
printf '%s' '{"session_id":"s","transcript_path":"/no/such.jsonl","hook_event_name":"Stop"}' \
  >"$TEST_TMPDIR/abort.in"
abort_err=$(bash "$HFA_COPY" <"$TEST_TMPDIR/abort.in" 2>&1 >/dev/null) || abort_rc=$?
assert_exit "injected exit 3 fails open (exit 0)" 0 "$abort_rc"
assert_contains "injected failure names the hook on stderr" "$abort_err" \
  "hook-failure-audit: did not run (status 3); fail-open"
abort_lines=$(printf '%s\n' "$abort_err" | grep -c . || true)
assert_eq "injected failure writes one stderr line" "1" "$abort_lines"

T_OV="$TEST_TMPDIR/overlap.jsonl"
DATA_OV="$TEST_TMPDIR/data-overlap"
make_transcript "$T_OV"
run_hook "$T_OV" "$DATA_OV" >"$TEST_TMPDIR/ov1.out" &
ov_pid1=$!
run_hook "$T_OV" "$DATA_OV" >"$TEST_TMPDIR/ov2.out" &
ov_pid2=$!
wait "$ov_pid1" "$ov_pid2"
ov_warns=$(cat "$TEST_TMPDIR/ov1.out" "$TEST_TMPDIR/ov2.out" | grep -c 'PreToolUse:Bash' || true)
if ((ov_warns >= 1 && ov_warns <= 2)); then
  ok "overlapping audits warn about a registration at most twice ($ov_warns)"
else
  bad "overlapping audits warn about a registration at most twice: got $ov_warns"
fi
assert_silent "a run after the overlapping pair is silent" "$(run_hook "$T_OV" "$DATA_OV")"
ov_cursor="$(find "$DATA_OV" -name '*.cursor' -type f | head -n 1)"
if [[ -n "$ov_cursor" ]] && [[ "$(sed -n 1p "$ov_cursor")" =~ ^b[0-9]+$ ]] && [[ "$(sed -n 2p "$ov_cursor")" == "$T_OV" ]]; then
  ok "overlapping audits leave a valid cursor file"
else
  bad "overlapping audits leave a valid cursor file: ${ov_cursor:-none found}"
fi

row="$(jq -c '[.hooks.Stop[].hooks[] | select((.command // "") | contains("hook-failure-audit.sh"))]' "$HOOK_DIR/hooks.json")"
assert_eq "one hook-failure-audit Stop row" "1" "$(jq 'length' <<<"$row")"
assert_eq "the row is shell-form bash with no args and no node" "true" \
  "$(jq '.[0] | .type == "command" and .shell == "bash" and (has("args") | not) and (.command | contains("node") | not)' <<<"$row")"
assert_eq "the row runs async so the audit stays off the Stop wall" "true" "$(jq '.[0].async == true' <<<"$row")"
row_cmd="$(jq -r '.[0].command' <<<"$row")"
row_rc=0
printf '%s' '{"session_id":"s","transcript_path":"/no/such.jsonl","hook_event_name":"Stop"}' \
  | CLAUDE_PLUGIN_ROOT="$(dirname "$HOOK_DIR")" CLAUDE_PLUGIN_DATA="$TEST_TMPDIR/row-data" \
    bash -c "$row_cmd" >/dev/null 2>&1 || row_rc=$?
assert_exit "the registered command line runs the hook and exits 0" 0 "$row_rc"

report
