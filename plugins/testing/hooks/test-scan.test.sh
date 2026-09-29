#!/usr/bin/env bash
# Contract test for test-scan.sh, the testing plugin's PostToolUse hook.
#
# Builds a throwaway git repository per run, writes test files into it, and
# pipes hand-built PostToolUse payloads through the hook. Covers the option
# gate (through the exec-form launcher), findings on a create, the once-per-
# file-per-agent rules note, Edit scoping to the changed block, the scanner
# timeout, gitignored paths, the doubtful-hit prompt (recomputed and derived
# expectations, constant restatements), the lead for findings of tests that
# can fail, the marker prune, and the per-call dedup that keeps two
# overlapping `if` rows from reporting twice.

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

# payload <tool> <file> <session> <agent> <tool_use_id> <tool_response json>
payload() {
  jq -cn --arg t "$1" --arg f "$2" --arg s "$3" --arg a "$4" --arg u "$5" --argjson r "$6" \
    '{hook_event_name: "PostToolUse", tool_name: $t, session_id: $s, tool_use_id: $u,
      tool_input: {file_path: $f}, tool_response: $r}
     | if $a == "" then . else . + {agent_id: $a} end'
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
assert_contains "(i) leads with tests that cannot fail" "$out" "tests that cannot fail"

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

echo
echo "$PASS passed, $FAIL failed"
((FAIL == 0))
