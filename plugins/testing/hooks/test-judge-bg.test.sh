#!/usr/bin/env bash
# Contract test for test-judge-bg.sh, the task-end judge's PostToolUse job
# (async): it judges the test blocks a write created or changed and writes
# their verdicts to the ledger. The judge is the stub behind TEST_JUDGE_CMD.
# shellcheck disable=SC2016,SC2034  # check() evals its single-quoted condition, which reads these

# shellcheck source=judge-test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/judge-test-helpers.sh"
HOOK="$HOOK_DIR/test-judge-bg.sh"
transcript s1 claude-sonnet-5
bg() { payload "$1" "$2" "$3" | bash "$HOOK"; }

# A created test is judged once and its verdict written by rename.
F="$REPO/src/add.test.ts"
js_file "$F" adds
record s1 w1 "$F" "$(blocks adds:1:3:5)"
out="$(bg s1 w1 "$F")"
assert_empty "nothing is printed" "$out"
check "a created test is judged once" '[[ "$(stub_calls)" == 1 ]]'
v="$(verdict_of s1 adds)"
assert_contains "its verdict is in the ledger" "$v" '"verdict":"PASS"'
assert_contains "the verdict records the model and effort" "$v" '"model":"opus","effort":"medium"'
check "the verdict was written by rename (no temp file left)" '[[ -z "$(find "$DATA/verdicts" -name ".*")" ]]'
check "the pending marker is removed" '[[ -z "$(find "$DATA/pending" -type f)" ]]'

# The judge command: the fixed flags, from the repository, with the recursion
# guard exported, never a real claude.
args="$(stub_args 1)"
for want in -p --model opus --effort medium --tools Read,Grep,Glob "Read($REPO/**)" "Grep($REPO/**)" "Glob($REPO/**)" \
  --settings '{"disableAllHooks":true}' --setting-sources --strict-mcp-config --disable-slash-commands \
  --max-budget-usd 0.90 --output-format json --no-session-persistence; do
  assert_contains "judge command carries $want" "$args" "$want"
done
assert_contains "the system prompt appends test-value section 1" "$args" "## 1. Every expected value names its independent source"
assert_contains "the system prompt is the prompt file" "$args" "You are a test judge."
assert_contains "the prompt names the block by ordinal, range and name" "$args" "block 1 3-5 adds"
check "the judge runs from the repository with TEST_JUDGE_ACTIVE=1" '[[ "$(cat "$STUB_DIR"/call-*.env)" == "$REPO 1" ]]'

# A second firing for a key with a verdict does nothing.
record s1 w1b "$F" "$(blocks adds:1:3:5)"
bg s1 w1b "$F"
check "a key with a verdict is not judged again" '[[ "$(stub_calls)" == 1 ]]'

# The session file written after the job starts is still found: the job
# reads it after the debounce.
stub_reset
G="$REPO/src/two.test.ts"
js_file "$G" first second
payload s1 w2 "$G" | TEST_JUDGE_DEBOUNCE=1 bash "$HOOK" &
sleep 0.3
record s1 w2 "$G" "$(blocks second:1:6:8)"
wait
check "a session file written during the debounce is found (only its block is judged)" \
  '[[ "$(stub_args 1)" == *"block 1 6-8 second"* && "$(stub_args 1)" != *"block 1 3-5 first"* ]]'

# A block changed during the debounce: the newer write's job owns it.
stub_reset
H="$REPO/src/changing.test.ts"
js_file "$H" changing
record s1 w3 "$H" "$(blocks changing:1:3:5)"
payload s1 w3 "$H" | TEST_JUDGE_DEBOUNCE=2 bash "$HOOK" &
# The job hashes the file right after writing its pending marker.
for _ in $(seq 1 40); do
  [[ -n "$(find "$DATA/pending" -name w3 2>/dev/null)" ]] && break
  sleep 0.1
done
sleep 0.3
js_file "$H" changing again
wait
check "a block changed during the debounce exits without judging" '[[ "$(stub_calls)" == 0 ]]'

# Inserting a test above a judged one neither re-judges it nor loses the new one.
stub_reset
before="$(verdict_files s1 | wc -l)"
printf '%s\n' "import { test, expect } from 'vitest';" "import { add } from './add';" \
  "test('inserted', () => {" "  expect(add(2, 2)).toBe(4);" "});" \
  "test('adds', () => {" "  expect(add(1, 2)).toBe(3);" "});" >"$F"
record s1 w4 "$F" "$(blocks inserted:1:3:5)"
bg s1 w4 "$F"
check "inserting a test above a judged one judges only the new one" \
  '[[ "$(stub_calls)" == 1 && "$(stub_args 1)" == *"block 1 3-5 inserted"* && "$(stub_args 1)" != *adds* ]]'
check "the judged one keeps its verdict" '[[ "$(verdict_files s1 | wc -l)" == $((before + 1)) && -n "$(verdict_of s1 adds)" ]]'

# A second firing finds the lock and exits: two jobs for one file, one run.
stub_reset
L="$REPO/src/locked.test.ts"
js_file "$L" locked
record s1 w5 "$L" "$(blocks locked:1:3:5)"
record s1 w6 "$L" "$(blocks locked:1:3:5)"
STUB_SLEEP=1 bg s1 w5 "$L" &
sleep 0.4
STUB_SLEEP=1 bg s1 w6 "$L"
wait
check "a second firing finds the lock and exits" '[[ "$(stub_calls)" == 1 ]]'

# The same call id fired twice (two matching `if` rows) runs once.
stub_reset
D="$REPO/src/dup.test.ts"
js_file "$D" dup
record s1 w7 "$D" "$(blocks dup:1:3:5)"
bg s1 w7 "$D"
rm -f "$DATA/verdicts/$PKEY/s1/"*
bg s1 w7 "$D"
check "one tool_use_id starts at most one job" '[[ "$(stub_calls)" == 1 ]]'

# A stale lock with a dead pid is broken and counted as one failed attempt.
stub_reset
S="$REPO/src/stale.test.ts"
js_file "$S" stale
record s1 w8 "$S" "$(blocks stale:1:3:5)"
# A pid that has already exited. Killing a fresh `sleep &` instead can land
# before its exec, while the child is still a copy of this shell holding its
# EXIT trap, which then removes $TMP under the running suite.
dead="$(sh -c 'echo $$')"
mkdir -p "$DATA/locks"
# Hold every lock the job might take: the key's hash is not known here, so
# pre-seed the job's first attempt to learn it, then plant a dead holder.
STUB_MODE=fail bg s1 w8 "$S"
kh="$(ls "$DATA/attempts")"
rm -f "$DATA/attempts/$kh"
printf '%s %s %s\n' "$dead" "${HOSTNAME:-localhost}" "$(date +%s)" >"$DATA/locks/$kh"
stub_reset
record s1 w9 "$S" "$(blocks stale:1:3:5)"
bg s1 w9 "$S"
check "a stale lock with a dead pid is broken" '[[ "$(stub_calls)" == 1 && -n "$(verdict_of s1 stale)" ]]'
check "the broken lock counts as one failed attempt" '[[ "$(wc -l <"$DATA/attempts/$kh")" -eq 1 ]]'
check "the lock is released" '[[ ! -e "$DATA/locks/$kh" ]]'

# Judge failure and judge timeout leave no verdict and release the lock.
for mode in fail hang; do
  stub_reset
  X="$REPO/src/$mode.test.ts"
  js_file "$X" "$mode"
  record s1 "w-$mode" "$X" "$(blocks "$mode:1:3:5")"
  began=$SECONDS
  STUB_MODE=$mode TEST_JUDGE_RUN_TIMEOUT=1 bg s1 "w-$mode" "$X"
  check "judge $mode: no verdict" '[[ -z "$(verdict_of s1 "$mode")" ]]'
  check "judge $mode: the lock is released" '[[ -z "$(find "$DATA/locks" -type f)" ]]'
  why="judge exited"
  [[ "$mode" == hang ]] && why="judge timed out"
  check "judge $mode: counted as a failed attempt ($why)" '[[ "$(cat "$DATA"/attempts/* | grep -c "$why")" == 1 ]]'
done
check "the hang guard ends a hanging judge" '((SECONDS - began < 15))'

# A run cut at its bound gives no verdict, even when the judge prints one
# after the watchdog has killed its tools.
stub_reset
L2="$REPO/src/late.test.ts"
js_file "$L2" late
record s1 w-late "$L2" "$(blocks late:1:3:5)"
STUB_SLEEP=5 TEST_JUDGE_RUN_TIMEOUT=1 bg s1 w-late "$L2"
check "a run cut at its bound writes no verdict" '[[ "$(stub_calls)" == 1 && -z "$(verdict_of s1 late)" ]]'

# The hang guard needs no coreutils timeout (stock macOS has none; on Git Bash
# only Windows' timeout.exe may resolve): with neither timeout nor gtimeout on
# PATH the judge still runs, and a hanging one is ended with its whole process
# group.
NOTO="$TMP/no-timeout-bin"
mkdir -p "$NOTO"
IFS=: read -ra dirs <<<"$PATH"
for d in "${dirs[@]}"; do
  for x in "$d"/*; do
    b="${x##*/}"
    [[ -x "$x" && ! -e "$NOTO/$b" && "$b" != timeout && "$b" != gtimeout ]] && ln -s "$x" "$NOTO/$b"
  done
done
check "the test PATH has no timeout or gtimeout" '! PATH="$NOTO" command -v timeout && ! PATH="$NOTO" command -v gtimeout'
stub_reset
W="$REPO/src/notimeout.test.ts"
js_file "$W" notimeout
record s1 w-noto "$W" "$(blocks notimeout:1:3:5)"
payload s1 w-noto "$W" | PATH="$NOTO" bash "$HOOK"
assert_contains "without timeout on PATH the judge runs and its verdict lands" "$(verdict_of s1 notimeout)" '"verdict":"PASS"'
stub_reset
W="$REPO/src/notimeout-hang.test.ts"
js_file "$W" nothang
record s1 w-noto2 "$W" "$(blocks nothang:1:3:5)"
rm -f "$STUB_DIR/hang.pid"
began=$SECONDS
payload s1 w-noto2 "$W" | PATH="$NOTO" STUB_MODE=hang TEST_JUDGE_RUN_TIMEOUT=1 bash "$HOOK"
check "without timeout on PATH a hanging judge is ended within the bound" '((SECONDS - began < 10)) && [[ -z "$(verdict_of s1 nothang)" ]]'
check "and its child dies with it (the whole process group)" '[[ -s "$STUB_DIR/hang.pid" ]] && ! kill -0 "$(cat "$STUB_DIR/hang.pid")" 2>/dev/null'
check "and the lock is released" '[[ -z "$(find "$DATA/locks" -type f)" ]]'

# A run that hits the malfunction budget gives UNKNOWN with that reason.
stub_reset
B="$REPO/src/budget.test.ts"
js_file "$B" budget
record s1 w10 "$B" "$(blocks budget:1:3:5)"
STUB_MODE=budget bg s1 w10 "$B"
assert_contains "a run that hits the budget gives UNKNOWN" "$(verdict_of s1 budget)" '"verdict":"UNKNOWN"'
assert_contains "with the budget named as the reason" "$(verdict_of s1 budget)" 'malfunction budget'
assert_contains "the malfunction is logged" "$(cat "$DATA/test-judge.log")" "malfunction"

# The per-run budget is $0.90 per started ten blocks.
stub_reset
E="$REPO/src/eleven.test.ts"
names=()
for i in $(seq 1 11); do names+=("t$i"); done
js_file "$E" "${names[@]}"
record s1 w11 "$E" null
bg s1 w11 "$E"
assert_contains "eleven blocks in one run get \$1.80" "$(stub_args 1)" $'--max-budget-usd\n1.80'
check "one run judges the whole file" '[[ "$(stub_calls)" == 1 && "$(verdict_files s1 | xargs grep -l "\"t1[01]\"" | wc -l)" == 2 ]]'

# An unset session cap means no limit; a set one is honored.
transcript s2 claude-sonnet-5
stub_reset
for i in 1 2 3; do
  js_file "$REPO/src/cap$i.test.ts" "cap$i"
  record s2 "c$i" "$REPO/src/cap$i.test.ts" "$(blocks "cap$i:1:3:5")"
  bg s2 "c$i" "$REPO/src/cap$i.test.ts"
done
check "an unset session cap means no limit" '[[ "$(stub_calls)" == 3 ]]'
transcript s3 claude-sonnet-5
stub_reset
for i in 1 2; do
  record s3 "d$i" "$REPO/src/cap$i.test.ts" "$(blocks "cap$i:1:3:5")"
  CLAUDE_PLUGIN_OPTION_TEST_JUDGE_SESSION_RUNS=1 bg s3 "d$i" "$REPO/src/cap$i.test.ts"
done
check "a session cap of 1 allows one run" '[[ "$(stub_calls)" == 1 ]]'

# The slot cap is honored: with three live runs on the machine, a job waits.
stub_reset
mkdir -p "$DATA/slots"
sleep 60 &
holder=$!
for i in 0 1 2; do printf '%s %s %s\n' "$holder" "${HOSTNAME:-localhost}" "$(date +%s)" >"$DATA/slots/$i"; done
Q="$REPO/src/slot.test.ts"
js_file "$Q" slot
record s1 w12 "$Q" "$(blocks slot:1:3:5)"
bg s1 w12 "$Q" &
job=$!
sleep 1.5
check "the slot cap is honored: no fourth run starts" '[[ "$(stub_calls)" == 0 ]]'
rm -f "$DATA/slots/1"
wait "$job"
kill "$holder" 2>/dev/null
check "the job runs once a slot frees" '[[ "$(stub_calls)" == 1 && -n "$(verdict_of s1 slot)" ]]'

# blocks:null means the whole file: every block --blocks lists is judged.
stub_reset
N="$REPO/src/null.test.ts"
js_file "$N" one two
record s1 w13 "$N" null
bg s1 w13 "$N"
check "blocks:null judges every block of the file" '[[ "$(stub_args 1)" == *"block 1 3-5 one"* && "$(stub_args 1)" == *"block 1 6-8 two"* ]]'

# A lost-sync file is one whole-file key.
stub_reset
printf '%s\n' '@test "a" {' "  run greet" "  [ \"\$status\" -eq 0 ]" "}" '@test "b" {' '  run greet "x' "}" >"$REPO/src/lost.bats"
record s1 w14 "$REPO/src/lost.bats" null
bg s1 w14 "$REPO/src/lost.bats"
check "a lost-sync file is one whole-file key" '[[ "$(stub_args 1)" == *"block 0 1-7 lost.bats"* && "$(stub_args 1 | grep -c "^block ")" == 1 ]]'

# A bash harness is one whole-file key; its changed lines go to the judge as a hint.
stub_reset
printf '%s\n' '#!/usr/bin/env bash' 'source ./harness.sh' 'check "adds" "$(add 1 2)" 3' 'check "subs" "$(sub 3 1)" 2' >"$REPO/src/math.test.sh"
record s1 w15 "$REPO/src/math.test.sh" "$(blocks math.test.sh:1:1:4)" "" "[3,4]"
bg s1 w15 "$REPO/src/math.test.sh"
assert_contains "a bash harness is one key" "$(stub_args 1)" "block 1 1-4 math.test.sh"
assert_contains "its changed lines travel as a hint" "$(stub_args 1)" "a hint to where the new tests are: 3,4"

# A job the Stop hook hands a late key to waits for the lock the Stop's dying
# run still holds, then judges the key; a write-time job does not wait.
stub_reset
Hd="$REPO/src/handoff.test.ts"
js_file "$Hd" handoff
record s1 w-hand "$Hd" "$(blocks handoff:1:3:5)"
STUB_MODE=fail bg s1 w-hand0 "$Hd"
kh="$(grep -l 'judge exited' "$DATA/attempts/"* | xargs ls -t | head -1)" && kh="${kh##*/}"
rm -f "$DATA/attempts/$kh"
sleep 20 &
dying=$!
printf '%s %s %s\n' "$dying" "${HOSTNAME:-localhost}" "$(date +%s)" >"$DATA/locks/$kh"
stub_reset
payload s1 w-hand-bg "$Hd" | bash "$HOOK"
check "a write-time job skips a key another live run holds" '[[ "$(stub_calls)" == 0 ]]'
(
  sleep 1.5
  rm -f "$DATA/locks/$kh"
) &
payload s1 stop-hand "$Hd" | TEST_JUDGE_HANDOFF=1 bash "$HOOK"
kill "$dying" 2>/dev/null
check "a handoff job waits for the held lock, then judges the key" '[[ "$(stub_calls)" == 1 && -n "$(verdict_of s1 handoff)" ]]'
wait

# TEST_JUDGE_ACTIVE=1 (inside a judge run) exits at once.
stub_reset
record s1 w16 "$REPO/src/cap1.test.ts" null
out="$(payload s1 w16 "$REPO/src/cap1.test.ts" | TEST_JUDGE_ACTIVE=1 bash "$HOOK")"
check "TEST_JUDGE_ACTIVE=1 exits at once" '[[ -z "$out" && "$(stub_calls)" == 0 ]]'
out="$(payload s1 w17 "$REPO/src/cap1.test.ts" | CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED='' bash "$HOOK")"
check "test_judge_enabled off: nothing runs" '[[ -z "$out" && "$(stub_calls)" == 0 ]]'

check "no real claude was ever called" '[[ ! -e "$TMP/real-claude-called" ]]'
finish
