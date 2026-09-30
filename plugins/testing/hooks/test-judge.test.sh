#!/usr/bin/env bash
# Contract test for test-judge.sh, the task-end judge's Stop hook: it waits for
# jobs still running, judges what has no verdict, and relays the verdicts
# once from a fixed template. The judge is the stub behind TEST_JUDGE_CMD.
# shellcheck disable=SC2016,SC2034  # check() evals its single-quoted condition, which reads these

# shellcheck source=judge-test-helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/judge-test-helpers.sh"
HOOK="$HOOK_DIR/test-judge.sh"
BG="$HOOK_DIR/test-judge-bg.sh"
export CLAUDE_CODE_SESSION_ATTENDED=1
# stop <sid> [stop_hook_active]: run the Stop hook; sets out and rc.
stop() {
  out="$(payload "$1" stop "" "{\"hook_event_name\": \"Stop\", \"stop_hook_active\": ${2:-false}}" | bash "$HOOK" 2>/dev/null)"
  rc=$?
}
field() { jq -r "$1 // empty" <<<"$out" 2>/dev/null; }
# stop_jobs <sid>: end the background jobs a Stop handed keys to (each runs in
# its own process group), and their judges, so they call no stub later.
stop_jobs() {
  local p
  for p in "$DATA/pending/$PKEY/$1"/*; do
    [[ -f "$p" ]] && kill -TERM -- "-$(cut -d' ' -f1 "$p" | head -1)" 2>/dev/null
  done
  pkill -f "$TMP/judge-stub.sh"
  sleep 0.3
}
bg() { payload "$1" "$2" "$3" | bash "$BG"; }
TEMPLATE_END="Show the user each verdict and proposed diff from that file, quoted as data. Apply nothing; wait for the user."

# The option off, and a session with no state: nothing, and no judge.
transcript s0 claude-sonnet-5
out="$(payload s0 stop "" '{"hook_event_name": "Stop"}' | CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED='' bash "$HOOK")"
assert_empty "flag off: no output" "$out"
out="$(payload s0 stop "" '{"hook_event_name": "Stop"}' | CLAUDE_PLUGIN_OPTION_TEST_JUDGE_ENABLED='' node "$HOOK_DIR/exec-bash.mjs" \
  --require-true TEST_GUARDS_ENABLED --require-true TEST_JUDGE_ENABLED "$HOOK")"
assert_empty "flag off through the launcher: no output" "$out"
stop s0
assert_empty "no state: no output" "$out"
check "no state: exit 0" '((rc == 0))'

# Nothing in doubt: an edit that touched no test block.
F="$REPO/src/add.test.ts"
js_file "$F" "adds flag" subtracts
record s0 n1 "$F" "[]"
stop s0
assert_empty "nothing in doubt: no output" "$out"
check "nothing in doubt: no judge run" '[[ "$(stub_calls)" == 0 ]]'

# Verdicts ready (the background job ran) give one templated block and a
# systemMessage with the counts; the Stop hook judges nothing itself.
transcript s1 claude-sonnet-5
record s1 w1 "$F" null
bg s1 w1 "$F"
stub_reset
stop s1
check "ready verdicts: the Stop hook runs no judge" '[[ "$(stub_calls)" == 0 ]]'
check "ready verdicts: one block" '[[ "$(field .decision)" == block ]]'
findings="$(field .reason | sed -n 's/.*Findings: \(.*\)\. Show the user.*/\1/p')"
check "the reason is the fixed template" \
  '[[ "$(field .reason)" == "The test judge reviewed 2 tests (1 FLAG, 1 PASS, 0 UNKNOWN). Findings: $findings. $TEMPLATE_END" ]]'
assert_contains "the systemMessage carries the counts" "$(field .systemMessage)" "2 tests (1 FLAG, 1 PASS, 0 UNKNOWN)"
assert_contains "the systemMessage carries the findings path" "$(field .systemMessage)" "$findings"
check "the findings file sits in the branch's review directory" '[[ "$findings" == "$REPO/.work/reviews/feat-judge-test/"*-test-judge.md && -f "$findings" ]]'
check "the memory root self-ignores" '[[ "$(cat "$REPO/.work/.gitignore")" == "*" ]]'
check "the findings file is a review-findings file for this branch" \
  '[[ "$(sed -n 2p "$findings")" == "type: review-findings" && "$(sed -n 4p "$findings")" == "branch: feat/judge-test" ]]'
# What the findings contract fixes: the table shape, and per row the rank,
# the crosswalk tier, a repo-relative Location, and a Finding cell led by the
# qualified rule id.
rows() { grep '^| [0-9]' "$1"; }
cells() { awk -F'|' '{ print NF - 2 }' <<<"${1//\\|/}"; }
check "the findings table has the contract's header" \
  'grep -qxF "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |" "$findings"'
check "one findings row, for the FLAG only (the PASS emits none)" '[[ "$(rows "$findings" | wc -l)" == 1 ]]'
row="$(rows "$findings")"
check "the row has the table's seven cells" '[[ "$(cells "$row")" == 7 ]]'
check "rank 1, the crosswalk tier SUGGESTION, Location at the block's repo-relative line" \
  '[[ "$(cut -d"|" -f2,3,5 <<<"$row")" == " 1 | SUGGESTION | src/add.test.ts:3 " ]]'
check "the Finding cell leads with the qualified rule id" '[[ "$(cut -d"|" -f7 <<<"$row")" == " testing/judge/rule-restated-expectation: "* ]]'
assert_contains "the findings file carries the proposed diff" "$(cat "$findings")" "+test('adds flag', () => { // judged"
assert_contains "and the PASS verdict with its evidence" "$(cat "$findings")" "> test('subtracts', () => {"
stop s1
assert_empty "a relayed set is not relayed again" "$out"

# stop_hook_active: never blocks or judges, even with unrelayed verdicts,
# which wait for the next task end.
transcript s2 claude-sonnet-5
G="$REPO/src/active.test.ts"
js_file "$G" active
record s2 w1 "$G" null
bg s2 w1 "$G"
stub_reset
stop s2 true
check "stop_hook_active: no block" '[[ "$(field .decision)" != block ]]'
check "stop_hook_active: no judge run" '[[ "$(stub_calls)" == 0 ]]'
stop s2
check "the unrelayed verdict is relayed at the next task end" '[[ "$(field .decision)" == block && "$(field .reason)" == *"reviewed 1 test "* ]]'

# A key with no job is judged at Stop, under the lock.
transcript s3 claude-sonnet-5
H="$REPO/src/nojob.test.ts"
js_file "$H" nojob
record s3 w1 "$H" null
stub_reset
stop s3
check "a key with no job is judged at Stop" '[[ "$(stub_calls)" == 1 && "$(field .reason)" == *"reviewed 1 test "* ]]'
check "and its lock is released" '[[ -z "$(find "$DATA/locks" -type f)" ]]'

# A live pending/ job is waited on, not judged twice.
transcript s4 claude-sonnet-5
P="$REPO/src/pending.test.ts"
js_file "$P" pending
record s4 w1 "$P" null
stub_reset
payload s4 w1 "$P" | TEST_JUDGE_DEBOUNCE=2 bash "$BG" &
sleep 0.5
stop s4
wait
check "a live pending/ job is waited on" '[[ "$(stub_calls)" == 1 && "$(field .reason)" == *"reviewed 1 test "* ]]'

# A live lock is waited on too: its holder writes the verdict.
transcript s5 claude-sonnet-5
K="$REPO/src/lockwait.test.ts"
js_file "$K" lockwait
record s5 w1 "$K" null
STUB_MODE=fail stop s5
kh="$(ls "$DATA/attempts")"
rm -f "$DATA/attempts/$kh"
sleep 20 &
holder=$!
printf '%s %s %s\n' "$holder" "${HOSTNAME:-localhost}" "$(date +%s)" >"$DATA/locks/$kh"
(
  sleep 1.5
  mkdir -p "$DATA/verdicts/$PKEY/s5"
  jq -cn --arg f "$K" --arg r "$REPO" '{file: $f, repo: $r, name: "lockwait", ordinal: 1, start: 3, end: 5, verdict: "PASS",
    evidence: ["  expect(add(1, 2)).toBe(3);"], source: "held", diff: "", reason: "", model: "haiku", effort: "low"}' >"$DATA/verdicts/$PKEY/s5/$kh.json"
  rm -f "$DATA/locks/$kh"
  kill "$holder"
) &
stub_reset
stop s5
wait
check "a live lock is waited on" '[[ "$(stub_calls)" == 0 && "$(field .reason)" == *"reviewed 1 test (0 FLAG, 1 PASS"* ]]'

# The 11th key: named, handed to a background job with a pending/ marker; the
# following stop_hook_active Stop does not block; its verdict is relayed at
# the next task end.
transcript s6 claude-sonnet-5
E="$REPO/src/eleven.test.ts"
names=()
for i in $(seq 1 11); do names+=("t$i"); done
js_file "$E" "${names[@]}"
record s6 w1 "$E" null
stub_reset
STUB_SLEEP=1 stop s6
check "ten keys are judged at Stop" '[[ "$(field .reason)" == *"reviewed 10 tests"* ]]'
assert_contains "the 11th key is named as waiting" "$(field .systemMessage)" "eleven.test.ts: t11"
check "the 11th key is handed to a background job with a pending/ marker" '[[ -n "$(find "$DATA/pending/$PKEY/s6" -type f)" ]]'
stop s6 true
check "the following stop_hook_active Stop does not block" '[[ "$(field .decision)" != block ]]'
for _ in $(seq 1 40); do
  [[ -z "$(find "$DATA/pending/$PKEY/s6" -type f)" ]] && break
  sleep 0.25
done
stop s6
check "the 11th verdict is relayed at the next task end" '[[ "$(field .reason)" == *"reviewed 1 test "* ]]'
check "the 11th was judged once, by the background job" '[[ "$(stub_calls)" == 2 ]]'

# An 11th key whose job died is judged at the next task end.
transcript s7 claude-sonnet-5
cp "$E" "$REPO/src/eleven2.test.ts"
record s7 w1 "$REPO/src/eleven2.test.ts" null
stub_reset
STUB_SLEEP=2 stop s7
# The job dies with its judge, as at `-p` teardown.
p="$(find "$DATA/pending/$PKEY/s7" -type f | head -1)"
kill "$(cut -d' ' -f1 "$p" | head -1)" 2>/dev/null
pkill -f "$TMP/judge-stub.sh"
sleep 0.3
stub_reset
stop s7
check "an 11th key whose job died is judged at the next task end" \
  '[[ "$(stub_calls)" == 1 && "$(stub_args 1)" == *"block 1 33-35 t11"* && "$(field .reason)" == *"reviewed 1 test "* ]]'

# Time budget exhaustion: a systemMessage naming the tests not judged and the
# time spent, and no block.
transcript s8 claude-sonnet-5
T="$REPO/src/slow.test.ts"
js_file "$T" slow
record s8 w1 "$T" null
stub_reset
STUB_MODE=hang TEST_JUDGE_TIMEOUT=1 stop s8
check "budget exhaustion: no block" '[[ "$(field .decision)" != block ]]'
assert_contains "budget exhaustion: names the test and the time" "$(field .systemMessage)" "slow.test.ts: slow"
check "budget exhaustion: states the time spent" '[[ "$(field .systemMessage)" =~ not\ judged\ in\ [0-9]+\ s ]]'
check "budget exhaustion: the key goes to a background job, as the overflow does" '[[ -n "$(find "$DATA/pending/$PKEY/s8" -type f)" ]]'
stop_jobs s8
sleep 0.5

# The Stop hook returns within TEST_JUDGE_TIMEOUT even when it must wait for a
# judge slot: with the machine's three slots held and one freed at 3 s, a
# 4 s bound and a judge that takes 8 s, it returns by about 6 s, exits 0, and
# hands the key to a background job.
transcript s8b claude-sonnet-5
T2="$REPO/src/slotwait.test.ts"
js_file "$T2" slotwait
record s8b w1 "$T2" null
mkdir -p "$DATA/slots"
sleep 30 &
holder=$!
for s in 0 1 2; do printf '%s %s %s\n' "$holder" "${HOSTNAME:-localhost}" "$(date +%s)" >"$DATA/slots/$s"; done
(
  sleep 3
  rm -f "$DATA/slots/1"
) &
t0=$EPOCHREALTIME
STUB_SLEEP=8 TEST_JUDGE_TIMEOUT=4 stop s8b
t1=$EPOCHREALTIME
elapsed=$(((${t1/./} - ${t0/./}) / 1000))
check "a slot wait does not carry the Stop hook past its bound (${elapsed} ms <= 6000)" '((elapsed <= 6000 && rc == 0))'
assert_contains "the key not judged in time is named" "$(field .systemMessage)" "slotwait.test.ts: slotwait"
check "and handed to a background job" '[[ -n "$(find "$DATA/pending/$PKEY/s8b" -type f)" ]]'
kill "$holder" 2>/dev/null
rm -f "$DATA/slots/"*
stop_jobs s8b
wait

# A judge that ignores TERM is still running at the deadline: its key is late,
# not "still judging". The hook returns within the bound plus the KILL grace
# and hands the key to a background job, which waits for the dying run's lock
# and then judges it.
cat >"$TMP/term-stub.sh" <<'EOF'
#!/usr/bin/env bash
trap '' TERM
printf x >"$STUB_DIR/call-term-$$.args"
end=$((SECONDS + 8))
while ((SECONDS < end)); do sleep 0.2; done
echo '{"type":"result","subtype":"success","is_error":false,"result":"{\"verdicts\":[]}"}'
EOF
chmod +x "$TMP/term-stub.sh"
transcript s8c claude-sonnet-5
T3="$REPO/src/termdeaf.test.ts"
js_file "$T3" termdeaf
record s8c w1 "$T3" null
t0=$EPOCHREALTIME
TEST_JUDGE_CMD="$TMP/term-stub.sh" TEST_JUDGE_TIMEOUT=4 stop s8c
t1=$EPOCHREALTIME
elapsed=$(((${t1/./} - ${t0/./}) / 1000))
check "a TERM-deaf judge: the hook returns within the bound plus the KILL grace (${elapsed} ms <= 10000)" '((elapsed <= 10000 && rc == 0))'
p="$(find "$DATA/pending/$PKEY/s8c" -type f | head -1)"
check "its key gets a pending/ marker and a live background job" '[[ -n "$p" ]] && kill -0 "$(head -1 "$p" | cut -d" " -f1)" 2>/dev/null'
assert_not_contains "the message does not call this Stop's own late run still judging" "$(field .systemMessage)" "still judging"
assert_contains "the message names the key as not judged in time" "$(field .systemMessage)" "termdeaf.test.ts: termdeaf"
stop_jobs s8c
pkill -f "$TMP/term-stub.sh"
wait

# Two failed attempts: "judge not run", and no third attempt.
transcript s9 claude-sonnet-5
X="$REPO/src/failing.test.ts"
js_file "$X" failing
record s9 w1 "$X" null
stub_reset
STUB_MODE=fail stop s9
assert_contains "a first failure is named as not judged" "$(field .systemMessage)" "not judged"
STUB_MODE=fail stop s9
assert_contains "2 failed attempts give judge not run" "$(field .systemMessage)" "judge not run for failing.test.ts: failing"
STUB_MODE=fail stop s9
check "no third attempt" '[[ "$(stub_calls)" == 2 ]]'

# The findings file follows .claude/topic-docs.yaml's memory_dir, but only to a
# root strictly inside the checkout; `..` or an outside path falls back to the
# plugin data directory and writes nothing outside.
mkdir -p "$REPO/.claude" "$TMP/outside"
for mem in notes '../escape' "$TMP/outside"; do
  sid="mem${#mem}"
  transcript "$sid" claude-sonnet-5
  W="$REPO/src/mem$sid.test.ts"
  js_file "$W" "mem$sid"
  record "$sid" w1 "$W" null
  printf 'memory_dir: %s\n' "$mem" >"$REPO/.claude/topic-docs.yaml"
  stop "$sid"
  f="$(field .systemMessage | sed -n 's/.*Findings: //p')"
  case "$mem" in
  notes) check "memory_dir inside the checkout is used" '[[ "$f" == "$REPO/notes/reviews/feat-judge-test/"* && -f "$REPO/notes/.gitignore" ]]' ;;
  *) check "memory_dir $mem outside the checkout: the plugin data directory" \
    '[[ "$f" == "$DATA/findings/"* && ! -e "$REPO/../escape" && ! -e "$TMP/outside/.gitignore" ]]' ;;
  esac
done
rm -rf "$REPO/.claude" "$REPO/notes"

# Relay validation: a quote not in the file, and a diff touching another
# file, are relayed as UNKNOWN.
for mode in badquote otherfile; do
  transcript "v$mode" claude-sonnet-5
  V="$REPO/src/$mode.test.ts"
  js_file "$V" "$mode flag"
  record "v$mode" w1 "$V" null
  STUB_MODE=$mode stop "v$mode"
  check "$mode: relayed as UNKNOWN" '[[ "$(field .reason)" == *"(0 FLAG, 0 PASS, 1 UNKNOWN)"* ]]'
done
f="$(field .reason | sed -n 's/.*Findings: \(.*\)\. Show the user.*/\1/p')"
assert_contains "the reason for a diff touching another file is recorded" "$(cat "$f")" "the proposed diff touches another file"
check "a FLAG that fails validation reaches no findings row" '[[ -z "$(rows "$f")" ]]'
assert_contains "the reason for a quote not in the file is recorded" "$(cat "$REPO"/.work/reviews/feat-judge-test/*)" "a quoted line is not in the file"

# An untouched test in an edited file is not in doubt; a new cant-fail-ok:
# marker is.
transcript s10 claude-sonnet-5
M="$REPO/src/marker.test.ts"
js_file "$M" untouched edited marked
awk 'NR == 10 { $0 = $0 " // cant-fail-ok: the vendor documents 3" } 1' "$M" >"$M.new" && mv "$M.new" "$M"
record s10 w1 "$M" "$(blocks edited:1:6:8)" "" null 0 "2026-09-30T10:00:00Z"
record s10 w2 "$M" "[]" "" null 1 "2026-09-30T10:01:00Z"
stub_reset
stop s10
check "an untouched test in an edited file is not in doubt" '[[ "$(stub_args 1)" != *untouched* ]]'
check "the edited test and the one with a new cant-fail-ok: marker are" \
  '[[ "$(stub_args 1)" == *"block 1 6-8 edited"* && "$(stub_args 1)" == *"block 1 9-11 marked"* ]]'

# In a file the session created there is no earlier count: a marker inside a
# block or on the line above it puts that block in doubt, even when the create
# record's own count already includes it.
transcript s11 claude-sonnet-5
C="$REPO/src/created.test.ts"
js_file "$C" plain above inside
awk 'NR == 6 { print "// cant-fail-ok: the vendor documents 3" } NR == 10 { $0 = $0 " // cant-fail-ok: external limit" } 1' \
  "$C" >"$C.new" && mv "$C.new" "$C"
CREATE=true record s11 w1 "$C" "$(blocks plain:1:3:5)" "" null 2
stub_reset
stop s11
check "a new file: a marker on the line above a block puts it in doubt" '[[ "$(stub_args 1)" == *"block 1 7-9 above"* ]]'
check "a new file: a marker inside a block puts it in doubt" '[[ "$(stub_args 1)" == *"block 1 10-12 inside"* ]]'

# The judge model: defaults, fallback, validation, and a class that differs
# from every writer.
model_for() { # model_for <sid> <env...>: the --model the Stop hook's judge run gets
  local sid="$1" Y="$REPO/src/model-$1.test.ts"
  shift
  js_file "$Y" "m$sid"
  record "$sid" w1 "$Y" null "${AGENT:-}"
  stub_reset
  out="$(payload "$sid" stop "" '{"hook_event_name": "Stop"}' | env "$@" bash "$HOOK" 2>/dev/null)"
  stub_args 1 | sed -n '/^--model$/{n;p;}'
}
transcript ma claude-sonnet-5
check "keys unset: opus" '[[ "$(model_for ma X=1)" == opus && "$(stub_args 1 | sed -n "/^--effort$/{n;p;}")" == medium ]]'
transcript mb claude-opus-5-5
check "keys unset, an opus writer: the sonnet fallback" '[[ "$(model_for mb X=1)" == sonnet ]]'
transcript mc claude-sonnet-5
check "an invalid alias falls back to opus, an invalid effort to medium" \
  '[[ "$(model_for mc CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL=gpt CLAUDE_PLUGIN_OPTION_TEST_JUDGE_EFFORT=ultra)" == opus &&
    "$(stub_args 1 | sed -n "/^--effort$/{n;p;}")" == medium ]]'
transcript md claude-opus-5-5
jq -cn '{type: "assistant", message: {model: "claude-opus-5-5", content: [{type: "tool_use", name: "Agent", input: {model: "haiku", prompt: "x"}}]}}' >>"$TDIR/md.jsonl"
jq -cn '{type: "assistant", message: {model: "<synthetic>", content: []}}' >>"$TDIR/md.jsonl"
check "Agent-call and <synthetic> lines do not change the session model" '[[ "$(model_for md X=1)" == sonnet ]]'
transcript me claude-sonnet-5
subagent me a1 claude-opus-5-5
check "class collisions walk opus, sonnet, haiku" \
  '[[ "$(AGENT=a1 model_for me CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL=sonnet CLAUDE_PLUGIN_OPTION_TEST_JUDGE_FALLBACK_MODEL=opus)" == haiku ]]'
transcript mf claude-opus-5-5
subagent mf a2 claude-sonnet-5
check "an opus main session with a sonnet subagent writing the test picks haiku" '[[ "$(AGENT=a2 model_for mf X=1)" == haiku ]]'
transcript mg claude-opus-5-5 claude-haiku-4-5-20251001
subagent mg a3 claude-sonnet-5
subagent mg a5 claude-opus-5-5
record mg w0 "$REPO/src/model-mg.test.ts" null a5
check "opus, sonnet and haiku all among the writers: no judge, never fable" '[[ -z "$(AGENT=a3 model_for mg X=1)" ]]'
assert_contains "and the key is UNKNOWN with the reason" "$(cat "$DATA/verdicts/$PKEY/mg/"*.json)" "no judge class differs from the writers"

# Unattended (CLAUDE_CODE_SESSION_ATTENDED not exactly 1): no block, the
# systemMessage and the findings file only.
transcript u1 claude-sonnet-5
U="$REPO/src/unattended.test.ts"
js_file "$U" unattended
record u1 w1 "$U" null
out="$(payload u1 stop "" '{"hook_event_name": "Stop"}' | CLAUDE_CODE_SESSION_ATTENDED=0 bash "$HOOK" 2>/dev/null)"
check "unattended: no block" '[[ "$(field .decision)" != block ]]'
assert_contains "unattended: the systemMessage carries the counts" "$(field .systemMessage)" "reviewed 1 test (0 FLAG, 1 PASS, 0 UNKNOWN)"

# A malformed state file is skipped; scanner exit 2 and a crash end in exit 0.
transcript z1 claude-sonnet-5
Z="$REPO/src/sturdy.test.ts"
js_file "$Z" sturdy
record z1 w1 "$Z" null
printf '{not json' >"$DATA/sessions/$PKEY/z1/broken.json"
stop z1
check "a malformed state file is skipped" '((rc == 0)) && [[ "$(field .reason)" == *"reviewed 1 test "* ]]'
transcript z2 claude-sonnet-5
record z2 w1 "$Z" null
printf '#!/usr/bin/env bash\nexit 2\n' >"$TMP/scanner-2.sh"
out="$(payload z2 stop "" '{"hook_event_name": "Stop"}' | TEST_SCAN_SCANNER="$TMP/scanner-2.sh" bash "$HOOK" 2>/dev/null)"
rc=$?
check "scanner exit 2: exit 0" '((rc == 0))'
printf 'mktemp() { : "$__unset_on_purpose"; }\n' >"$TMP/crash.sh"
transcript z3 claude-sonnet-5
record z3 w1 "$Z" null
out="$(payload z3 stop "" '{"hook_event_name": "Stop"}' | BASH_ENV="$TMP/crash.sh" bash "$HOOK" 2>/dev/null)"
rc=$?
check "a crash in the script: exit 0 and no partial output" '((rc == 0)) && [[ -z "$out" ]]'

# TEST_JUDGE_ACTIVE=1 exits at once.
stub_reset
out="$(payload z1 stop "" '{"hook_event_name": "Stop"}' | TEST_JUDGE_ACTIVE=1 bash "$HOOK")"
check "TEST_JUDGE_ACTIVE=1 exits at once" '[[ -z "$out" && "$(stub_calls)" == 0 ]]'

# A test file a Bash call created (bashEditDiff recorded) is recorded by the
# Bash route of test-scan and judged at the Stop; no background job runs for
# a Bash call.
transcript sbash claude-sonnet-5
BF="$REPO/src/bashmade.test.ts"
js_file "$BF" bashmade
jq -cn --arg t "$TDIR/sbash.jsonl" --arg c "$REPO" --arg f "$BF" '{hook_event_name: "PostToolUse", tool_name: "Bash",
  session_id: "sbash", tool_use_id: "tb1", transcript_path: $t, cwd: $c, tool_input: {command: "gen"},
  tool_response: {stdout: "", stderr: "", interrupted: false, bashEditDiff: {changedFiles: [$f], moreFiles: 0,
    files: [{filePath: $f, created: true, hunks: [{oldStart: 0, oldLines: 0, newStart: 1, newLines: 5, lines: ["+x"]}]}]}}}' |
  bash "$HOOK_DIR/test-scan-bash.sh" >/dev/null 2>&1
stub_reset
stop sbash
check "a Bash-written test file is judged at the Stop" '[[ "$(stub_calls)" == 1 && "$(stub_args 1)" == *"block 1 3-5 bashmade"* && "$(field .reason)" == *"reviewed 1 test "* ]]'

# A judge run whose parent died before splitting its output leaves a raw file
# in the ledger directory; the next Stop harvests it instead of judging again.
transcript h1 claude-sonnet-5
O="$REPO/src/orphan.test.ts"
js_file "$O" orphan
record h1 w1 "$O" null
STUB_MODE=fail stop h1
kh="$(grep -l . "$DATA/attempts/"* | xargs ls -t | head -1)"
kh="${kh##*/}"
rm -f "$DATA/attempts/$kh"
d="$DATA/verdicts/$PKEY/h1"
mkdir -p "$d"
jq -cn --arg f "$O" --arg r "$REPO" --arg k "$kh" '{file: $f, repo: $r, model: "sonnet", effort: "low", budget: "0.90",
  keys: [{kh: $k, ordinal: 1, start: 3, end: 5, name: "orphan"}]}' >"$d/.run-1-1.keys"
jq -cn --arg r '{"verdicts": [{"name": "orphan", "ordinal": 1, "verdict": "PASS", "evidence": ["  expect(add(1, 2)).toBe(3);"], "source": "hand-computed", "diff": ""}]}' \
  '{type: "result", subtype: "success", is_error: false, result: $r}' >"$d/.run-1-1"
stub_reset
stop h1
check "an orphaned raw run is harvested, not judged again" '[[ "$(stub_calls)" == 0 && "$(field .reason)" == *"reviewed 1 test (0 FLAG, 1 PASS"* ]]'
check "and the raw file is removed" '[[ -z "$(find "$d" -name ".run-*")" ]]'

# Successors: a /clear or fork successor adopts the sessions whose last write
# falls within the hour before it started.
START="$HOOK_DIR/test-judge-start.sh"
now="$(date +%s)"
# A project key of their own, so the sessions above are not adopted.
TDIR="$TMP/transcripts/-successors"
mkdir -p "$TDIR"
PKEY="$(printf '%s\n%s' "$REPO" "$TDIR" | sha256 | cut -c1-16)"
iso() { jq -rn --argjson t "$1" '$t | todate'; }
start() { payload "$1" start "" "{\"hook_event_name\": \"SessionStart\", \"source\": \"$2\"}" | bash "$START" 2>/dev/null; }
# A predecessor with one unrelayed verdict and one block never judged.
transcript pa claude-sonnet-5
A1="$REPO/src/pred.test.ts"
js_file "$A1" judged unjudged
record pa w1 "$A1" "$(blocks judged:1:3:5)" "" null 0 "$(iso $((now - 600)))"
bg pa w1 "$A1"
record pa w2 "$A1" "$(blocks unjudged:1:6:8)" "" null 0 "$(iso $((now - 300)))"
transcript ca claude-sonnet-5
start ca clear >/dev/null
stub_reset
stop ca
check "after a clear marker, the predecessor's in-doubt block is judged" '[[ "$(stub_calls)" == 1 && "$(stub_args 1)" == *"block 1 6-8 unjudged"* ]]'
check "and its unrelayed verdict relayed with it" '[[ "$(field .reason)" == *"reviewed 2 tests"* ]]'
transcript cb claude-sonnet-5
start cb clear >/dev/null
stub_reset
stop cb
assert_empty "a verdict the predecessor already relayed is not relayed again" "$out"
# A session without a marker adopts nothing.
transcript pb claude-sonnet-5
B1="$REPO/src/pred2.test.ts"
js_file "$B1" orphan
record pb w1 "$B1" null "" null 0 "$(iso $((now - 600)))"
bg pb w1 "$B1"
transcript nb claude-sonnet-5
record nb w1 "$REPO/src/add.test.ts" "[]"
stop nb
assert_empty "a session without a marker adopts nothing" "$out"
transcript cm claude-sonnet-5
start cm compact >/dev/null
record cm w1 "$REPO/src/add.test.ts" "[]"
stop cm
assert_empty "a compact session (same id, SessionStart source compact) adopts nothing" "$out"
# A sibling whose last write postdates the marker is not adopted.
transcript cc claude-sonnet-5
start cc clear >/dev/null
transcript sib claude-sonnet-5
S1="$REPO/src/sibling.test.ts"
js_file "$S1" sibling
record sib w1 "$S1" null "" null 0 "$(iso $((now + 120)))"
bg sib w1 "$S1"
stop cc
check "a sibling whose last write postdates the marker is not adopted" '[[ "$out" != *sibling* && "$(field .reason)" != *"reviewed"*"sibling"* ]]'
check "while the marker adopts pb, within the hour" '[[ "$(field .reason)" == *"reviewed 1 test "* ]]'
# A session whose last write is over an hour before the marker is not adopted;
# the SessionStart catch-up names its verdicts instead.
transcript po claude-sonnet-5
O1="$REPO/src/old.test.ts"
js_file "$O1" old
record po w1 "$O1" null "" null 0 "$(iso $((now - 7200)))"
bg po w1 "$O1"
transcript cd claude-sonnet-5
out="$(start cd clear)"
assert_contains "the successor's SessionStart catch-up names its verdicts instead" "$(field .systemMessage)" \
  "1 test (0 FLAG, 1 PASS, 0 UNKNOWN)"
record cd w1 "$REPO/src/add.test.ts" "[]"
stop cd
check "and its Stop does not adopt that session" '[[ "$(field .reason)" != *reviewed* ]]'
transcript ce claude-sonnet-5
out="$(start ce startup)"
assert_empty "the catch-up names them once" "$out"
# A startup session relays its own verdict even when an older session relayed
# one for identical block text.
transcript st claude-sonnet-5
record st w1 "$A1" "$(blocks judged:1:3:5)"
bg st w1 "$A1"
stop st
check "a startup session relays its own verdict for block text another session relayed" '[[ "$(field .reason)" == *"reviewed 1 test "* ]]'

check "no real claude was ever called" '[[ ! -e "$TMP/real-claude-called" ]]'
finish
