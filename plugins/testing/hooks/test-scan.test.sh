#!/usr/bin/env bash
# Contract test for test-scan.sh, the testing plugin's PostToolUse hook.
#
# Builds a throwaway git repository per run, writes test files into it, and
# pipes hand-built PostToolUse payloads through the hook. Covers the option
# gate (through the exec-form launcher), findings on a create, the once-per-
# file-per-agent rules note, Edit scoping to the changed block, the scanner
# timeout, gitignored paths, the doubtful-hit prompt (recomputed and derived
# expectations, constant restatements), the lead for findings of tests that
# can fail, the marker prune, the per-call dedup that keeps two
# overlapping `if` rows from reporting twice, and the per-write session state
# (blocks, project key, prune) the task-end judge reads.

# shellcheck disable=SC2016 # fence lines in fixtures are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/test-scan.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
assert_contains() {
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else fail "$1 (missing: $3; got: ${2:0:400})"; fi
}
assert_not_contains() {
  if [[ "$2" != *"$3"* ]]; then ok "$1"; else fail "$1 (unexpected: $3)"; fi
}
assert_empty() {
  if [[ -z "$2" ]]; then ok "$1"; else fail "$1 (got: ${2:0:400})"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# The recorders skip files under the temp root. These fixtures live under the
# real temp dir, so point that root at a directory that holds none of them.
# A case below aims it at its own copy (#6037).
export TEST_SCAN_SKIP_ROOT="$TMP/scan-skip-root"
mkdir -p "$TEST_SCAN_SKIP_ROOT"
REPO="$TMP/repo"
mkdir -p "$REPO/src" "$REPO/scratch"
git -C "$REPO" init -q
printf 'scratch/\n' >"$REPO/.gitignore"
export CLAUDE_PLUGIN_DATA="$TMP/data"
export CLAUDE_PROJECT_DIR="$REPO"
export HOME="$TMP/home"
export CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED=true

cat >"$REPO/src/sum.test.ts" <<'EOF'
import { test, expect } from 'vitest';
import { sum } from './sum';

test('adds', () => {
  sum(1, 2);
});
EOF

cat >"$REPO/src/mixed.test.ts" <<'EOF'
import { test, expect } from 'vitest';
import { sum } from './sum';

test('adds', () => {
  sum(1, 2);
});

test('adds two', () => {
  expect(sum(1, 2)).toBe(3);
});
EOF

cat >"$REPO/src/again.test.ts" <<'EOF'
import { test, expect } from 'vitest';
import { sum } from './sum';

test('adds', () => {
  expect(sum(1, 2)).toBe(sum(1, 2));
});
EOF

cat >"$REPO/src/limit.test.ts" <<'EOF'
import { test, expect } from 'vitest';
import { MAX_ITEMS } from './sum';

test('caps the cart', () => {
  expect(MAX_ITEMS).toBe(50);
});
EOF

cat >"$REPO/src/derived.test.ts" <<'EOF'
import { test, expect } from 'vitest';
import { add } from './sum';

test('adds', () => {
  expect(add(a, b)).toBe(a + b);
});
EOF

cat >"$REPO/src/weak.test.ts" <<'EOF'
import { test, expect } from 'vitest';
import { sum } from './sum';

test('adds', () => {
  expect(sum(1, 2)).toBeDefined();
});
EOF

cp "$REPO/src/sum.test.ts" "$REPO/scratch/ignored.test.ts"

# payload <tool> <file> <session> <agent> <tool_use_id> <tool_response json>;
# TPATH (empty: no transcript_path) and PCWD fill the session-state fields.
TPATH="$TMP/transcripts/-repo/main.jsonl"
PCWD="$REPO"
payload() {
  jq -cn --arg t "$1" --arg f "$2" --arg s "$3" --arg a "$4" --arg u "$5" --argjson r "$6" \
    --arg tp "$TPATH" --arg c "$PCWD" \
    '{hook_event_name: "PostToolUse", tool_name: $t, session_id: $s, tool_use_id: $u,
      cwd: $c, transcript_path: $tp, tool_input: {file_path: $f}, tool_response: $r}
     | if $a == "" then . else . + {agent_id: $a} end
     | if $tp == "" then del(.transcript_path) else . end'
}
# rec <session> <tool_use_id>: the session file written for that call, or "".
rec() { find "$CLAUDE_PLUGIN_DATA/sessions" -path "*/$1/$2.json" 2>/dev/null | head -1; }
# assert_jq <name> <file> <jq filter that must print true>
assert_jq() {
  if [[ -f "$2" ]] && [[ "$(jq "$3" "$2" 2>/dev/null)" == true ]]; then ok "$1"; else fail "$1 ($3 on ${2:-no file}: $(cat "$2" 2>/dev/null))"; fi
}
CREATE='{"type":"create","structuredPatch":[]}'
N=0
run() {
  N=$((N + 1))
  out="$(payload "$1" "$2" "${3:-s1}" "${4:-}" "${5:-call-$N}" "${6:-$CREATE}" | bash "$HOOK" 2>/dev/null)"
  rc=$?
}

# (a) option unset: the launcher never starts the hook.
out="$(payload Write "$REPO/src/sum.test.ts" s0 "" call-a "$CREATE" |
  CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED='' node "$HOOK_DIR/exec-bash.mjs" \
    --require-true TEST_GUARDS_ENABLED "$HOOK" 2>&1)"
assert_empty "(a) option unset: no output" "$out"
out="$(payload Write "$REPO/src/sum.test.ts" s0 "" call-a2 "$CREATE" |
  CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED='' bash "$HOOK" --enabled 2>&1)"
assert_contains "(a) --enabled, the consumer-entry form, runs with the option unset" "$out" rule-zero-assertion

# (b) a zero-assertion Vitest create reports the rule, with the rules note.
run Write "$REPO/src/sum.test.ts"
if [[ $rc -eq 0 ]]; then ok "(b) exits 0"; else fail "(b) exit $rc"; fi
assert_contains "(b) names rule-zero-assertion" "$out" "rule-zero-assertion"
assert_contains "(b) goes back through additionalContext" "$out" '"additionalContext"'
assert_contains "(b) first write carries the rules note" "$out" "testing:test-value"

# (c) the note is once per session + agent + file.
run Write "$REPO/src/sum.test.ts"
assert_contains "(c) findings still reported on a repeat write" "$out" "rule-zero-assertion"
assert_not_contains "(c) same session and agent: no second note" "$out" "testing:test-value"
run Write "$REPO/src/sum.test.ts" s1 agent-2
assert_contains "(c) a different agent_id gets the note" "$out" "testing:test-value"

# (d) an Edit touching only the good block leaves the bad block silent.
EDIT_GOOD='{"structuredPatch":[{"oldStart":9,"oldLines":1,"newStart":9,"newLines":1,
  "lines":["-  expect(sum(1, 2)).toBe(4);","+  expect(sum(1, 2)).toBe(3);"]}]}'
run Edit "$REPO/src/mixed.test.ts" s1 "" "" "$EDIT_GOOD"
assert_not_contains "(d) untouched bad block stays quiet" "$out" "rule-zero-assertion"
EDIT_BAD='{"structuredPatch":[{"oldStart":5,"oldLines":1,"newStart":5,"newLines":1,
  "lines":["-  sum(2, 2);","+  sum(1, 2);"]}]}'
run Edit "$REPO/src/mixed.test.ts" s1 "" "" "$EDIT_BAD"
assert_contains "(d) an Edit inside the bad block reports it" "$out" "rule-zero-assertion"

# (e) a hanging scanner is cut off: exit 0 and a log line.
cat >"$TMP/hang.sh" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
began=$SECONDS
out="$(payload Write "$REPO/src/sum.test.ts" s9 "" call-e "$CREATE" |
  TEST_SCAN_SCANNER="$TMP/hang.sh" TEST_SCAN_TIMEOUT=1 bash "$HOOK" 2>/dev/null)"
rc=$?
if [[ $rc -eq 0 ]]; then ok "(e) timeout exits 0"; else fail "(e) exit $rc"; fi
if ((SECONDS - began < 5)); then
  ok "(e) returns before the hooks.json timeout"
else
  fail "(e) took $((SECONDS - began))s"
fi
assert_contains "(e) logs the timeout" "$(cat "$CLAUDE_PLUGIN_DATA/test-scan.log" 2>/dev/null)" "timed out"
assert_jq "(e) a timed-out scan records blocks:null, meaning the whole file" "$(rec s9 call-e)" '.blocks == null'

# (e) the timeout ends the scanner's children too, not just its shell.
cat >"$TMP/spawn.sh" <<EOF
#!/usr/bin/env bash
sleep 30 &
echo \$! >"$TMP/child.pid"
wait
EOF
payload Write "$REPO/src/sum.test.ts" s9 "" call-e2 "$CREATE" |
  TEST_SCAN_SCANNER="$TMP/spawn.sh" TEST_SCAN_TIMEOUT=1 bash "$HOOK" >/dev/null 2>&1
sleep 0.2
if kill -0 "$(cat "$TMP/child.pid")" 2>/dev/null; then
  kill "$(cat "$TMP/child.pid")"
  fail "(e) a child the scanner spawned outlives the timeout"
else
  ok "(e) the timeout kills the scanner's children"
fi

# (f) a gitignored test file is left alone.
run Write "$REPO/scratch/ignored.test.ts"
assert_empty "(f) gitignored path: no output" "$out"

# (g) a recomputed expectation asks where the expected value comes from.
run Write "$REPO/src/again.test.ts"
assert_contains "(g) names rule-recomputed-expectation" "$out" "rule-recomputed-expectation"
assert_contains "(g) asks for the expected value's source" "$out" "where the expected value"

# (h) a constant restatement carries the same prompt, under a change-detector
# lead rather than the can't-fail one.
run Write "$REPO/src/limit.test.ts"
assert_contains "(h) names rule-constant-restatement" "$out" "rule-constant-restatement"
assert_contains "(h) asks for the expected value's source" "$out" "where the expected value"
assert_contains "(h) leads with change detectors" "$out" "fail on harmless changes"
assert_not_contains "(h) does not call a change detector a test that cannot fail" "$out" "tests that cannot fail"

# The markers are files created exclusively, not directories.
if [[ -f "$CLAUDE_PLUGIN_DATA/marks/call-call-1" ]] && [[ -z "$(find "$CLAUDE_PLUGIN_DATA/marks" -mindepth 1 -type d)" ]]; then
  ok "markers are plain files"
else
  fail "markers are plain files"
fi

# The 7-day prune removes old markers of both shapes: files, and the
# directories the earlier mkdir scheme left behind.
mkdir -p "$CLAUDE_PLUGIN_DATA/marks/call-old-dir"
touch "$CLAUDE_PLUGIN_DATA/marks/call-old-file"
touch -d '10 days ago' "$CLAUDE_PLUGIN_DATA/marks/call-old-dir" "$CLAUDE_PLUGIN_DATA/marks/call-old-file"
run Write "$REPO/src/sum.test.ts"
if [[ ! -e "$CLAUDE_PLUGIN_DATA/marks/call-old-dir" && ! -e "$CLAUDE_PLUGIN_DATA/marks/call-old-file" ]]; then
  ok "prune: old marker files and directories are removed"
else
  fail "prune: old marker files and directories are removed"
fi
if [[ -f "$CLAUDE_PLUGIN_DATA/marks/call-call-1" ]]; then ok "prune: a fresh marker stays"; else fail "prune: a fresh marker stays"; fi

# (i) a recomputed-derived expectation carries the doubtful-hit prompt.
run Write "$REPO/src/derived.test.ts"
assert_contains "(i) names rule-recomputed-derived" "$out" "rule-recomputed-derived"
assert_contains "(i) asks for the expected value's source" "$out" "where the expected value"
assert_contains "(i) leads with tests that check little" "$out" "tests that check little"
assert_not_contains "(i) does not call a derived expectation a test that cannot fail" "$out" "tests that cannot fail"

# (j) a weak oracle alone can fail, so it is not called a test that cannot fail.
run Write "$REPO/src/weak.test.ts"
assert_contains "(j) names rule-weak-oracle" "$out" "rule-weak-oracle"
assert_not_contains "(j) does not call a weak oracle a test that cannot fail" "$out" "tests that cannot fail"
assert_not_contains "(j) a weak oracle carries no doubtful-hit prompt" "$out" "where the expected value"

# Two overlapping `if` rows run the hook twice for one call; only one reports.
run Write "$REPO/src/sum.test.ts" s1 "" dup-call
first="$out"
run Write "$REPO/src/sum.test.ts" s1 "" dup-call
assert_contains "dedup: first run for a tool_use_id reports" "$first" "rule-zero-assertion"
assert_empty "dedup: second run for the same tool_use_id is silent" "$out"

# An invalid .claude/testing.yaml is named back to the agent, at its line, and
# the resolver's own message is logged.
mkdir -p "$REPO/.claude"
printf 'adapters:\n  enable: [js-vitset]\n' >"$REPO/.claude/testing.yaml"
run Write "$REPO/src/sum.test.ts"
assert_contains "config error: the agent is told the config is invalid" "$out" "testing.yaml:2: unknown adapter: js-vitset"
assert_contains "config error: in additionalContext" "$out" '"additionalContext"'
assert_contains "config error: the log holds the resolver's message" "$(cat "$CLAUDE_PLUGIN_DATA/test-scan.log")" "unknown adapter: js-vitset"
rm -f "$REPO/.claude/testing.yaml"
# The same error in a docs convention file's config block names the .md file and line.
mkdir -p "$REPO/docs/conventions"
printf '# Testing\n\nRules.\n\n```yaml config\nadapters:\n  enable: [js-vitset]\n```\n' >"$REPO/docs/conventions/testing.md"
run Write "$REPO/src/sum.test.ts"
assert_contains "docs block config error: named at the .md file and its line" "$out" "docs/conventions/testing.md:7: unknown adapter: js-vitset"
# With a .claude file too, the resolver's both-exist warning is not the error the agent is told.
printf 'paths:\n  exclude: [x]\n' >"$REPO/.claude/testing.yaml"
run Write "$REPO/src/sum.test.ts"
assert_contains "both locations: the agent is told the block's error, not the warning" "$out" "docs/conventions/testing.md:7: unknown adapter: js-vitset"
assert_empty "and the context does not carry the warning" "$(grep -F 'both exist' <<<"$out")"
rm -rf "$REPO/docs" "$REPO/.claude/testing.yaml"

# The plugin hook and the consumer settings entry share one marker directory,
# so the same call through both reports once and notes once.
C="$HOME/.claude/plugins/cache/mk/testing"
mkdir -p "$C"
ln -s "$(cd "$HOOK_DIR/.." && pwd)" "$C/1.0.0"
p="$(payload Write "$REPO/src/sum.test.ts" s-both "" call-both "$CREATE")"
first="$(CLAUDE_PLUGIN_DATA="$HOME/.claude/plugins/data/testing-mk" bash "$C/1.0.0/hooks/test-scan.sh" <<<"$p" 2>/dev/null)"
consumer() { env -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED= bash "$C/1.0.0/hooks/test-scan.sh" --enabled 2>/dev/null; }
out="$(consumer <<<"$p")"
assert_contains "shared markers: the plugin path reports" "$first" "rule-zero-assertion"
assert_empty "shared markers: the consumer entry does not report the same call again" "$out"
payload Write "$REPO/src/sum.test.ts" s-note "" call-note-1 "$CREATE" |
  CLAUDE_PLUGIN_DATA="$HOME/.claude/plugins/data/testing-mk" bash "$C/1.0.0/hooks/test-scan.sh" >/dev/null 2>&1
out="$(payload Write "$REPO/src/sum.test.ts" s-note "" call-note-2 "$CREATE" | consumer)"
assert_contains "shared markers: a later call through the consumer entry still reports" "$out" "rule-zero-assertion"
assert_not_contains "shared markers: but does not repeat the note" "$out" "testing:test-value"
out="$(payload Write "$REPO/src/sum.test.ts" s-state "" call-state "$CREATE" |
  env -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED= XDG_STATE_HOME="$TMP/state" bash "$HOOK" --enabled 2>/dev/null)"
if [[ -f "$TMP/state/claude-testing/marks/call-call-state" ]]; then
  ok "outside the plugin cache, markers go under XDG_STATE_HOME, never TMPDIR"
else
  fail "outside the plugin cache, markers go under XDG_STATE_HOME, never TMPDIR"
fi

# Session state: one file per scanned write under
# sessions/<pkey>/<session_id>/<tool_use_id>.json, naming the blocks the
# write created or changed, for the task-end judge.
S="$CLAUDE_PLUGIN_DATA/sessions"
run Write "$REPO/src/mixed.test.ts" st1 "" st-create
f="$(rec st1 st-create)"
assert_jq "state: a create records every block" "$f" \
  '.blocks == [{name: "adds", ordinal: 1, start: 4, end: 6}, {name: "adds two", ordinal: 1, start: 8, end: 10}]'
assert_jq "state: file, repo (the git toplevel), create and no agent" "$f" \
  ".file == \"$REPO/src/mixed.test.ts\" and .repo == \"$REPO\" and .create == true and .agent_id == null"
assert_jq "state: marker count 0" "$f" '.ok_markers == 0'
assert_jq "state: written_at is a UTC timestamp" "$f" '.written_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")'
run Edit "$REPO/src/mixed.test.ts" st1 agent-7 st-edit "$EDIT_GOOD"
f="$(rec st1 st-edit)"
assert_jq "state: an edit records only the edited block" "$f" '.blocks == [{name: "adds two", ordinal: 1, start: 8, end: 10}]'
assert_jq "state: an edit is not a create, and names its agent" "$f" '.create == false and .agent_id == "agent-7"'
assert_jq "state: an edit records the lines it wrote, the judge's bash-harness hint" "$f" '.lines == [9]'
assert_jq "state: a create records lines:null, meaning the whole file" "$(rec st1 st-create)" '.lines == null'
printf '%s\n' "import { test, expect } from 'vitest';" "test('caps', () => {" "  expect(cap(60)).toBe(50);" "});" >"$REPO/src/clean.test.ts"
run Write "$REPO/src/clean.test.ts" st1 "" st-clean
assert_jq "state: a clean file still records its blocks" "$(rec st1 st-clean)" '.blocks == [{name: "caps", ordinal: 1, start: 2, end: 4}]'
printf '%s\n' "import { test, expect } from 'vitest';" "// cant-fail-ok: the vendor documents 50" "test('caps', () => {" \
  "  expect(MAX).toBe(50); // cant-fail-ok: external API limit" "});" >"$REPO/src/marked.test.ts"
run Write "$REPO/src/marked.test.ts" st1 "" st-marked
assert_jq "state: the cant-fail-ok: markers in the file are counted" "$(rec st1 st-marked)" '.ok_markers == 2'
DEL='{"structuredPatch":[{"oldStart":5,"oldLines":1,"newStart":5,"newLines":0,"lines":["-  sum(3, 3);"]}]}'
run Edit "$REPO/src/mixed.test.ts" st1 "" st-del "$DEL"
assert_jq "state: a deletion-only edit records blocks:null and lines:null" "$(rec st1 st-del)" '.blocks == null and .lines == null'
run Edit "$REPO/src/mixed.test.ts" st1 "" st-nopatch '{}'
assert_jq "state: an edit with no patch records blocks:null and lines:null" "$(rec st1 st-nopatch)" '.blocks == null and .lines == null'
# A block the lexer loses (a string open at the end of the file) is not
# listed, so the record says the whole file rather than only the blocks
# the scanner could read.
printf '%s\n' '@test "a" {' "  run greet" "  [ \"\$status\" -eq 0 ]" "}" '@test "b" {' '  run greet "x' "}" >"$REPO/src/lost.bats"
run Write "$REPO/src/lost.bats" st1 "" st-lost
assert_jq "state: a block the lexer lost makes the record blocks:null" "$(rec st1 st-lost)" '.blocks == null'

# Two writes in parallel leave two files.
payload Write "$REPO/src/sum.test.ts" st2 "" st-par-1 "$CREATE" | bash "$HOOK" >/dev/null 2>&1 &
payload Write "$REPO/src/sum.test.ts" st2 "" st-par-2 "$CREATE" | bash "$HOOK" >/dev/null 2>&1 &
wait
if [[ -n "$(rec st2 st-par-1)" && -n "$(rec st2 st-par-2)" ]] && jq -e . "$(rec st2 st-par-1)" "$(rec st2 st-par-2)" >/dev/null; then
  ok "state: two parallel writes give two whole files"
else
  fail "state: two parallel writes give two whole files"
fi

# Nothing is written for an ignored path, an unsafe or empty id, or a payload
# with no transcript_path.
run Write "$REPO/scratch/ignored.test.ts" st1 "" st-ign
assert_empty "state: a gitignored path writes nothing" "$(rec st1 st-ign)"
run Write "$REPO/src/sum.test.ts" "../x" "" st-dots
assert_empty "state: a session id with ../ writes nothing" "$(find "$CLAUDE_PLUGIN_DATA" -name st-dots.json)"
payload Write "$REPO/src/sum.test.ts" "" "" st-nosid "$CREATE" | bash "$HOOK" >/dev/null 2>&1
assert_empty "state: an empty session id writes nothing" "$(find "$CLAUDE_PLUGIN_DATA" -name st-nosid.json)"
run Write "$REPO/src/sum.test.ts" st3 "" "a.b"
assert_contains "state: an unsafe tool_use_id still gets its findings" "$out" "rule-zero-assertion"
assert_empty "state: an unsafe tool_use_id writes nothing" "$(find "$S" -path '*/st3/*')"
TPATH="" run Write "$REPO/src/sum.test.ts" st4 "" st-notp
assert_empty "state: a missing transcript_path writes nothing" "$(find "$S" -path '*/st4/*')"

# The project key: the first 16 hex of the sha256 of the project directory, a
# newline and the transcript directory. The literal was worked out once from
# that formula with sha256sum, outside this hook.
P=/nonexistent/proj
TP=/nonexistent/transcripts/-proj
CLAUDE_PROJECT_DIR=$P TPATH="$TP/a.jsonl" run Write "$REPO/src/sum.test.ts" pk1 "" pk-a
assert_contains "pkey: sha256 of <project dir>\\n<transcript dir>, 16 hex" "$(rec pk1 pk-a)" "/sessions/297a19f13bd5fbd8/pk1/pk-a.json"
CLAUDE_PROJECT_DIR=$P TPATH="$TP/b.jsonl" run Write "$REPO/src/sum.test.ts" pk2 "" pk-b
assert_contains "pkey: a second session id in the same project and transcript directory shares the key" "$(rec pk2 pk-b)" "/sessions/297a19f13bd5fbd8/pk2/"
CLAUDE_PROJECT_DIR=$P TPATH="$TP/b.jsonl" PCWD="$REPO/src" run Write "$REPO/src/sum.test.ts" pk3 "" pk-c
assert_contains "pkey: a payload cwd moved by cd keeps the key while CLAUDE_PROJECT_DIR is set" "$(rec pk3 pk-c)" "/sessions/297a19f13bd5fbd8/pk3/"
CLAUDE_PROJECT_DIR=$P TPATH="/nonexistent/transcripts/-other/c.jsonl" run Write "$REPO/src/sum.test.ts" pk4 "" pk-d
f="$(rec pk4 pk-d)"
if [[ -n "$f" && "$f" != */297a19f13bd5fbd8/* ]]; then ok "pkey: another transcript directory gives another key"; else fail "pkey: another transcript directory gives another key ($f)"; fi
out="$(PCWD=$P TPATH="$TP/e.jsonl" payload Write "$REPO/src/sum.test.ts" pk5 "" pk-e "$CREATE" | env -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>/dev/null)"
assert_contains "pkey: without CLAUDE_PROJECT_DIR the payload cwd is the project directory" "$(rec pk5 pk-e)" "/sessions/297a19f13bd5fbd8/pk5/"

# Session state and the Phase 3 judge state are pruned after 7 days, at every
# depth.
mkdir -p "$S/oldkey/oldsid" "$CLAUDE_PLUGIN_DATA/verdicts/oldkey/oldsid" "$CLAUDE_PLUGIN_DATA/locks" \
  "$CLAUDE_PLUGIN_DATA/pending/oldkey/oldsid" "$CLAUDE_PLUGIN_DATA/runs/oldkey/oldsid" "$CLAUDE_PLUGIN_DATA/findings"
old=("$S/oldkey/oldsid/old.json" "$CLAUDE_PLUGIN_DATA/verdicts/oldkey/oldsid/v.json" "$CLAUDE_PLUGIN_DATA/locks/l"
  "$CLAUDE_PLUGIN_DATA/pending/oldkey/oldsid/p" "$CLAUDE_PLUGIN_DATA/runs/oldkey/oldsid/r" "$CLAUDE_PLUGIN_DATA/findings/f.md")
touch "${old[@]}"
touch -d '10 days ago' "${old[@]}"
run Write "$REPO/src/sum.test.ts" st5 "" st-prune
if [[ -z "$(find "${old[@]}" 2>/dev/null)" ]]; then
  ok "prune: nested state older than 7 days is removed"
else
  fail "prune: nested state older than 7 days is removed"
fi
if [[ -n "$(rec st5 st-prune)" && -n "$(rec st1 st-create)" ]]; then ok "prune: fresh session files stay"; else fail "prune: fresh session files stay"; fi
mkdir -p "$S/emptykey/emptysid" "$S/newkey/newsid"
touch -d '2 hours ago' "$S/emptykey/emptysid"
run Write "$REPO/src/sum.test.ts" st5 "" st-prune2
if [[ ! -e "$S/emptykey/emptysid" ]]; then ok "prune: an empty directory over an hour old is removed"; else fail "prune: an empty directory over an hour old is removed"; fi
if [[ -d "$S/newkey/newsid" ]]; then ok "prune: a fresh empty directory stays for its writer"; else fail "prune: a fresh empty directory stays for its writer"; fi

# Bash route: test-scan-bash.sh reads tool_response.bashEditDiff and runs
# test-scan.sh per changed test file.
BASH_HOOK="$HOOK_DIR/test-scan-bash.sh"
# bash_payload <tool_use_id> <bashEditDiff json, or "" for none>
bash_payload() {
  jq -cn --arg u "$1" --arg d "$2" --arg tp "$TPATH" --arg c "$PCWD" '{hook_event_name: "PostToolUse", tool_name: "Bash",
    session_id: "sb", tool_use_id: $u, transcript_path: $tp, cwd: $c, tool_input: {command: "true"},
    tool_response: {stdout: "", stderr: "", interrupted: false}}
    | if $d == "" then . else .tool_response.bashEditDiff = ($d | fromjson) end'
}
# diff_of <created|edit> <file> [hunks json]: a one-file bashEditDiff
diff_of() {
  jq -cn --arg k "$1" --arg f "$2" --argjson h "${3:-[]}" '{changedFiles: [$f], moreFiles: 0,
    files: [{filePath: $f, hunks: $h} + (if $k == "created" then {created: true} else {} end)]}'
}
ADD_ALL='[{"oldStart":0,"oldLines":0,"newStart":1,"newLines":1,"lines":["+x"]}]'
bash_run() {
  out="$(bash_payload "$1" "$2" | bash "$BASH_HOOK" 2>/dev/null)"
  rc=$?
}

bash_run bash-1 "$(diff_of created "$REPO/src/sum.test.ts" "$ADD_ALL")"
if [[ $rc -eq 0 ]]; then ok "(f) Bash: exits 0"; else fail "(f) Bash: exit $rc"; fi
assert_contains "(f) a created zero-assertion test file reports rule-zero-assertion" "$out" "rule-zero-assertion"
assert_contains "(f) the finding goes back through additionalContext" "$out" '"additionalContext"'

bash_run bash-2 ""
assert_empty "(g) no bashEditDiff: no output" "$out"
if [[ $rc -eq 0 ]]; then ok "(g) no bashEditDiff: exits 0"; else fail "(g) no bashEditDiff: exit $rc"; fi
bash_run bash-3 "$(diff_of edit "$REPO/src/app.ts" "$ADD_ALL")"
assert_empty "(g) only non-test files changed: no output" "$out"
bash_run bash-4 '{"changedFiles":[],"moreFiles":0,"files":[]}'
assert_empty "(g) an empty diff: no output" "$out"
out="$(bash_payload bash-5 "$(diff_of created "$REPO/src/sum.test.ts" "$ADD_ALL")" |
  CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED='' node "$HOOK_DIR/exec-bash.mjs" \
    --require-true TEST_GUARDS_ENABLED "$BASH_HOOK" 2>&1)"
assert_empty "(g) option unset: the launcher never starts the hook" "$out"
out="$(bash_payload bash-5b "$(diff_of created "$REPO/src/sum.test.ts" "$ADD_ALL")" |
  CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED='' bash "$BASH_HOOK" 2>&1)"
assert_empty "(g) option unset: nothing runs" "$out"

# Scope follows hook-precision rule 1: an edited file reports only blocks its
# hunks touch; a file listed without hunks reports nothing.
bash_run bash-6 "$(diff_of edit "$REPO/src/mixed.test.ts" "$(jq -c .structuredPatch <<<"$EDIT_GOOD")")"
assert_not_contains "(h) a Bash edit inside the good block leaves the bad block quiet" "$out" "rule-zero-assertion"
bash_run bash-7 "$(diff_of edit "$REPO/src/mixed.test.ts" "$(jq -c .structuredPatch <<<"$EDIT_BAD")")"
assert_contains "(h) a Bash edit inside the bad block reports it" "$out" "rule-zero-assertion"
bash_run bash-8 "$(jq -cn --arg f "$REPO/src/mixed.test.ts" '{changedFiles: [$f], moreFiles: 0, files: []}')"
assert_empty "(h) a changed file past the hunk list reports nothing" "$out"
bash_run bash-9 "$(diff_of created "$REPO/scratch/ignored.test.ts" "$ADD_ALL")"
assert_empty "(h) a gitignored test file is skipped" "$out"

# Two test files in one call each report, in one document.
two="$(jq -cn --arg a "$REPO/src/sum.test.ts" --arg b "$REPO/src/again.test.ts" --argjson h "$ADD_ALL" \
  '{changedFiles: [$a, $b], moreFiles: 0,
    files: [{filePath: $a, created: true, hunks: $h}, {filePath: $b, created: true, hunks: $h}]}')"
bash_run bash-10 "$two"
assert_contains "(i) two files: the first reports" "$out" "rule-zero-assertion"
assert_contains "(i) two files: the second reports" "$out" "rule-recomputed-expectation"
if [[ "$(jq -s length <<<"$out" 2>/dev/null)" == 1 ]]; then ok "(i) two files: one JSON document"; else fail "(i) two files: one JSON document (got: ${out:0:300})"; fi

# A scanner that fails is reported on stderr, as on the Write and Edit route.
cat >"$TMP/fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
err="$(bash_payload bash-11 "$(diff_of created "$REPO/src/sum.test.ts" "$ADD_ALL")" |
  TEST_SCAN_SCANNER="$TMP/fail.sh" bash "$BASH_HOOK" 2>&1 >/dev/null)"
assert_contains "(k) a failing scanner's diagnostic reaches stderr" "$err" "scanner exited 3"

# A test file a Bash call changed leaves the same session record as a Write or
# Edit, so the task-end judge covers it: one per changed test file, keyed by
# the call's tool_use_id and the file's place in the call.
bash_run bs-1 "$(diff_of created "$REPO/src/mixed.test.ts" "$ADD_ALL")"
assert_jq "Bash state: a created file records every block, as a create" "$(rec sb bs-1-1)" \
  '.create == true and .lines == null and (.blocks | map(.name)) == ["adds", "adds two"] and .file == "'"$REPO"'/src/mixed.test.ts"'
bash_run bs-2 "$(diff_of edit "$REPO/src/mixed.test.ts" "$(jq -c .structuredPatch <<<"$EDIT_GOOD")")"
assert_jq "Bash state: an edit records the block its hunk touched and the lines it wrote" "$(rec sb bs-2-1)" \
  '.create == false and .lines == [9] and .blocks == [{name: "adds two", ordinal: 1, start: 8, end: 10}]'
bash_run bs-3 "$(jq -cn --arg f "$REPO/src/mixed.test.ts" '{changedFiles: [$f], moreFiles: 0, files: []}')"
assert_jq "Bash state: a changed file with no hunks records blocks:null, the whole file" "$(rec sb bs-3-1)" '.blocks == null'
bash_run bs-4 "$two"
check_two="$(rec sb bs-4-1) $(rec sb bs-4-2)"
if [[ "$check_two" == *"/sb/bs-4-1.json "*"/sb/bs-4-2.json" ]]; then ok "Bash state: two test files in one call leave two records"; else fail "Bash state: two test files in one call leave two records ($check_two)"; fi

# A test file a checkout, pull or merge brought in is unchanged from HEAD in
# its own repository, as git diff sees it, and git last moved HEAD with that
# checkout, pull or merge: the session did not write it, so it is neither
# scanned nor recorded. One the call changed, or one HEAD lacks, is.
gc() { git -C "$1" -c commit.gpgsign=false -c user.name=t -c user.email=t@t "${@:2}"; }
HR="$TMP/headrepo"
mkdir -p "$HR/src"
git -C "$HR" init -q
cp "$REPO/src/sum.test.ts" "$HR/src/kept.test.ts"
cp "$REPO/src/sum.test.ts" "$HR/src/also.test.ts"
git -C "$HR" add -A
gc "$HR" commit -qm init
git -C "$HR" checkout -q -b work
# The hunk covers the zero-assertion test body (line 5), so a scan would report it.
BODY='[{"oldStart":5,"oldLines":1,"newStart":5,"newLines":1,"lines":["-  sum(1, 2);","+  sum(1, 2);"]}]'
bash_run hd-1 "$(diff_of edit "$HR/src/kept.test.ts" "$BODY")"
assert_not_contains "Bash HEAD: a test file identical to HEAD is not scanned" "$out" "rule-zero-assertion"
assert_empty "Bash HEAD: a test file identical to HEAD gives no output" "$out"
assert_empty "Bash HEAD: a test file identical to HEAD leaves no record" "$(rec sb hd-1-1)"
printf '%s\n' "test('more', () => {" "  sum(2, 2);" "});" >>"$HR/src/kept.test.ts"
bash_run hd-2 "$(diff_of edit "$HR/src/kept.test.ts" "$ADD_ALL")"
assert_contains "Bash HEAD: an edited tracked test file is recorded" "$(rec sb hd-2-1)" "/sb/hd-2-1.json"
cp "$REPO/src/sum.test.ts" "$HR/src/fresh.test.ts"
bash_run hd-3 "$(diff_of created "$HR/src/fresh.test.ts" "$ADD_ALL")"
assert_contains "Bash HEAD: an untracked new test file is recorded" "$(rec sb hd-3-1)" "/sb/hd-3-1.json"
# The repository is the file's own, found at either separator: a
# backslash-only path (a Windows path) to a file identical to HEAD stays quiet.
b=$'\\'
if command -v cygpath >/dev/null; then BS="$(cygpath -w "$HR/src/also.test.ts")"; else BS="${HR//\//$b}${b}src${b}also.test.ts"; fi
out="$(bash_payload hd-4 "$(diff_of edit "$BS" "$ADD_ALL")" | bash "$BASH_HOOK" 2>&1)"
assert_empty "Bash HEAD: a backslash path to a file identical to HEAD is not scanned" "$out"
assert_empty "Bash HEAD: a backslash path to a file identical to HEAD leaves no record" "$(rec sb hd-4-1)"
# A tracked test edited and committed in one call matches HEAD afterwards, but
# a commit last moved HEAD, so it is still recorded for the judge.
cp "$REPO/src/sum.test.ts" "$HR/src/mine.test.ts"
git -C "$HR" add src/mine.test.ts
gc "$HR" commit -qm mine
printf '%s\n' "test('mine', () => {" "  sum(3, 3);" "});" >>"$HR/src/mine.test.ts"
gc "$HR" commit -qm weaken src/mine.test.ts
bash_run hd-6 "$(diff_of edit "$HR/src/mine.test.ts" "$ADD_ALL")"
assert_contains "Bash HEAD: a test edited and committed in one call is recorded" "$(rec sb hd-6-1)" "/sb/hd-6-1.json"
# Test files a merge brought in stay quiet, and do not take the cap's slots
# from a new test file the same call wrote.
git -C "$HR" checkout -q -b side
for i in 1 2 3 4; do cp "$REPO/src/sum.test.ts" "$HR/src/p$i.test.ts"; done
git -C "$HR" add src/p1.test.ts src/p2.test.ts src/p3.test.ts src/p4.test.ts
gc "$HR" commit -qm side
git -C "$HR" checkout -q work
gc "$HR" merge -q --no-edit side
bash_run hd-7 "$(diff_of edit "$HR/src/p1.test.ts" "$BODY")"
assert_empty "Bash HEAD: a test file a merge brought in gives no output" "$out"
assert_empty "Bash HEAD: a test file a merge brought in leaves no record" "$(rec sb hd-7-1)"
cp "$REPO/src/sum.test.ts" "$HR/src/new.test.ts"
five="$(jq -cn --arg d "$HR/src" --argjson h "$ADD_ALL" '[range(1; 5) | "\($d)/p\(.).test.ts"] + ["\($d)/new.test.ts"]
  | {changedFiles: ., moreFiles: 0, files: map({filePath: ., hunks: $h})}')"
bash_run hd-8 "$five"
assert_jq "Bash HEAD: a new test file after four merged ones is still recorded" "$(rec sb hd-8-1)" '.file == "'"$HR"'/src/new.test.ts"'
# A file committed with CRLF line endings under core.autocrlf=true is
# unchanged to git, though hash-object's eol filter hashes it differently.
CR="$TMP/crlfrepo"
mkdir -p "$CR/src"
git -C "$CR" init -q
git -C "$CR" config core.autocrlf false
printf '%s\r\n' "import { test, expect } from 'vitest';" "import { sum } from './sum';" "" "test('adds', () => {" "  sum(1, 2);" "});" >"$CR/src/crlf.test.ts"
git -C "$CR" add -A
gc "$CR" commit -qm init
git -C "$CR" checkout -q -b work
git -C "$CR" config core.autocrlf true
out="$(bash_payload hd-5 "$(diff_of edit "$CR/src/crlf.test.ts" "$BODY")" | bash "$BASH_HOOK" 2>&1)"
assert_empty "Bash HEAD: a CRLF test file unchanged under core.autocrlf=true is not scanned" "$out"
assert_empty "Bash HEAD: a CRLF test file unchanged under core.autocrlf=true leaves no record" "$(rec sb hd-5-1)"

# A working copy under the temp root, or in a Claude session scratchpad, is
# not a test the session authored: no judge record (#6037). The skip root is
# injectable so the fixtures above still record.
mkdir -p "$REPO/hold" "$REPO/claude/proj/sess/scratchpad" "$REPO/KYLESE~1"
cp "$REPO/src/sum.test.ts" "$REPO/hold/copied.test.ts"
cp "$REPO/src/sum.test.ts" "$REPO/claude/proj/sess/scratchpad/pad.test.ts"
cp "$REPO/src/sum.test.ts" "$REPO/KYLESE~1/short.test.ts"
# The assignment has to sit on the hook, not the payload: a prefix on the
# left of a pipeline does not reach the right-hand command.
out="$(payload Write "$REPO/hold/copied.test.ts" stskip "" sk-temp "$CREATE" |
  TEST_SCAN_SKIP_ROOT="$REPO/hold" bash "$HOOK" 2>/dev/null)"
assert_empty "temp copy: no judge record" "$(rec stskip sk-temp)"
run Write "$REPO/claude/proj/sess/scratchpad/pad.test.ts" stskip "" sk-pad
assert_empty "scratchpad copy: no judge record" "$(rec stskip sk-pad)"
mkdir -p "$TMP/shortbin"
cat >"$TMP/shortbin/cygpath" <<EOF
#!/usr/bin/env bash
printf '%s\n' '$REPO/KYLESE~1'
EOF
chmod +x "$TMP/shortbin/cygpath"
out="$(payload Write "$REPO/KYLESE~1/short.test.ts" stskip "" sk-short "$CREATE" |
  TEST_SCAN_SKIP_ROOT="$TEST_SCAN_SKIP_ROOT" TESTING_OSTYPE=msys PATH="$TMP/shortbin:$PATH" bash "$HOOK" 2>/dev/null)"
assert_empty "8.3 short temp copy: no judge record" "$(rec stskip sk-short)"
out="$(bash_payload sk-bash "$(diff_of created "$REPO/hold/copied.test.ts" "$ADD_ALL")" |
  TEST_SCAN_SKIP_ROOT="$REPO/hold" bash "$BASH_HOOK" 2>/dev/null)"
assert_empty "Bash temp copy: no judge record" "$(rec sb sk-bash-1)"
out="$(bash_payload sk-pad "$(diff_of created "$REPO/claude/proj/sess/scratchpad/pad.test.ts" "$ADD_ALL")" |
  bash "$BASH_HOOK" 2>/dev/null)"
assert_empty "Bash scratchpad copy: no judge record" "$(rec sb sk-pad-1)"

# With TMPDIR, TMP and TEMP all unset, the POSIX defaults /tmp and /var/tmp
# are still the temp root. The fixtures are made there by name, not through
# mktemp's TMPDIR. The control shows the same copy records once the root is
# elsewhere, so the quiet cases are not quiet for another reason.
DEF_TMP="$(mktemp -d /tmp/test-scan-default.XXXXXX)"
VAR_TMP="$(mktemp -d /var/tmp/test-scan-default.XXXXXX 2>/dev/null)" || VAR_TMP=""
trap 'rm -rf "$TMP" "$DEF_TMP" ${VAR_TMP:+"$VAR_TMP"}' EXIT
cp "$REPO/src/sum.test.ts" "$DEF_TMP/def.test.ts"
run Write "$DEF_TMP/def.test.ts" stskip "" sk-def-control
assert_contains "control: a /tmp copy records when the root is elsewhere" "$(rec stskip sk-def-control)" sk-def-control
out="$(payload Write "$DEF_TMP/def.test.ts" stskip "" sk-def "$CREATE" |
  env -u TEST_SCAN_SKIP_ROOT -u TMPDIR -u TMP -u TEMP bash "$HOOK" 2>/dev/null)"
assert_empty "temp vars unset: a /tmp copy leaves no judge record" "$(rec stskip sk-def)"
out="$(bash_payload sk-def-bash "$(diff_of created "$DEF_TMP/def.test.ts" "$ADD_ALL")" |
  env -u TEST_SCAN_SKIP_ROOT -u TMPDIR -u TMP -u TEMP bash "$BASH_HOOK" 2>/dev/null)"
assert_empty "temp vars unset: a Bash /tmp copy leaves no judge record" "$(rec sb sk-def-bash-1)"
if [[ -n "$VAR_TMP" ]]; then
  cp "$REPO/src/sum.test.ts" "$VAR_TMP/var.test.ts"
  out="$(payload Write "$VAR_TMP/var.test.ts" stskip "" sk-var "$CREATE" |
    env -u TEST_SCAN_SKIP_ROOT -u TMPDIR -u TMP -u TEMP bash "$HOOK" 2>/dev/null)"
  assert_empty "temp vars unset: a /var/tmp copy leaves no judge record" "$(rec stskip sk-var)"
fi

# Git Bash reports TMP and TEMP as /tmp, its usertemp mount of the Windows
# temp folder, while the payload names the file by its long drive path. The
# stub answers cygpath -l with the long spelling and -s with the short one.
mkdir -p "$REPO/posixtmp" "$REPO/Long Temp" "$REPO/LONGTE~1"
cp "$REPO/src/sum.test.ts" "$REPO/Long Temp/long.test.ts"
cp "$REPO/src/sum.test.ts" "$REPO/LONGTE~1/short.test.ts"
mkdir -p "$TMP/formbin"
cat >"$TMP/formbin/cygpath" <<EOF
#!/usr/bin/env bash
form="\$1"
shift 2
[[ "\${1:-}" == -- ]] && shift
for _ in "\$@"; do
  case "\$form" in
  -l) printf '%s\n' '$REPO/Long Temp' ;;
  -s) printf '%s\n' '$REPO/LONGTE~1' ;;
  *) printf '%s\n' "\$_" ;;
  esac
done
EOF
chmod +x "$TMP/formbin/cygpath"
out="$(payload Write "$REPO/Long Temp/long.test.ts" stskip "" sk-long "$CREATE" |
  TEST_SCAN_SKIP_ROOT="$REPO/posixtmp" TESTING_OSTYPE=msys PATH="$TMP/formbin:$PATH" bash "$HOOK" 2>/dev/null)"
assert_empty "POSIX-spelled temp var, long payload path: no judge record" "$(rec stskip sk-long)"
out="$(payload Write "$REPO/LONGTE~1/short.test.ts" stskip "" sk-long-short "$CREATE" |
  TEST_SCAN_SKIP_ROOT="$REPO/posixtmp" TESTING_OSTYPE=msys PATH="$TMP/formbin:$PATH" bash "$HOOK" 2>/dev/null)"
assert_empty "POSIX-spelled temp var, short payload path: no judge record" "$(rec stskip sk-long-short)"
out="$(bash_payload sk-long-bash "$(diff_of created "$REPO/Long Temp/long.test.ts" "$ADD_ALL")" |
  TEST_SCAN_SKIP_ROOT="$REPO/posixtmp" TESTING_OSTYPE=msys PATH="$TMP/formbin:$PATH" bash "$BASH_HOOK" 2>/dev/null)"
assert_empty "POSIX-spelled temp var, Bash long path: no judge record" "$(rec sb sk-long-bash-1)"

echo
echo "$PASS passed, $FAIL failed"
((FAIL == 0))
