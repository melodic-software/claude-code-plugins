#!/usr/bin/env bash
# Contract test for test-weaken.sh, the testing plugin's PreToolUse hook.
#
# Builds a throwaway git repository per run, writes test files into it, and
# pipes hand-built PreToolUse payloads through the hook. Covers the option
# gate, the advisory context (removed assertion, added skip, removed test
# block, changed expected literal) with no permissionDecision, the deny path
# behind rules.test-weaken-block and its test-change: marker, fail-open on a
# scanner error and a hang, silence on a pure addition, a create, a
# gitignored or excluded path and an unjudgeable fragment, the per-call dedup,
# and that test-scan still reports for a call test-weaken already saw.
# test-scope: plugins/testing/skills/audit/adapters/*.yaml

set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/test-weaken.sh"

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
# assert_no_decision <name> <output>: the document carries no permissionDecision.
assert_no_decision() {
  if jq -e '.hookSpecificOutput.permissionDecision' <<<"$2" >/dev/null 2>&1; then
    fail "$1 (got a decision: ${2:0:400})"
  else
    ok "$1"
  fi
}
assert_deny() {
  if [[ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$2" 2>/dev/null)" == deny ]]; then
    ok "$1"
  else
    fail "$1 (got: ${2:0:400})"
  fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"
mkdir -p "$REPO/src" "$REPO/scratch" "$REPO/legacy"
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
  expect(sum(1, 2)).toBe(3);
  expect(sum(2, 2)).toBe(4);
});

test('adds zero', () => {
  expect(sum(0, 0)).toBe(0);
});
EOF
cp "$REPO/src/sum.test.ts" "$REPO/scratch/ignored.test.ts"
cp "$REPO/src/sum.test.ts" "$REPO/legacy/old.test.ts"

cat >"$REPO/src/test_calc.py" <<'EOF'
from calc import add


def test_add():
    assert add(1, 2) == 3
EOF

# payload <tool> <file> <tool_use_id> <tool_input json without file_path>
payload() {
  jq -cn --arg t "$1" --arg f "$2" --arg u "$3" --argjson i "$4" \
    '{hook_event_name: "PreToolUse", tool_name: $t, session_id: "s1", tool_use_id: $u,
      tool_input: ({file_path: $f} + $i)}'
}
# edit_input <old_string> <new_string>
edit_input() {
  jq -cn --arg o "$1" --arg n "$2" '{old_string: $o, new_string: $n, replace_all: false}'
}
N=0
# run <tool> <file> <tool_input json> [env assignments...]
run() {
  N=$((N + 1))
  local tool="$1" file="$2" input="$3"
  shift 3
  out="$(payload "$tool" "$file" "call-$N" "$input" | env "$@" bash "$HOOK" 2>/dev/null)"
  rc=$?
}
block_on() {
  mkdir -p "$REPO/.claude"
  printf 'rules:\n  test-weaken-block: error\n' >"$REPO/.claude/testing.yaml"
}
block_off() { rm -f "$REPO/.claude/testing.yaml"; }

DROP_EXPECT="$(edit_input $'  expect(sum(1, 2)).toBe(3);\n  expect(sum(2, 2)).toBe(4);' '  expect(sum(1, 2)).toBe(3);')"
ADD_SKIP="$(edit_input "test('adds zero', () => {" "test.skip('adds zero', () => {")"
ADD_SKIP_MARKED="$(edit_input "test('adds zero', () => {" \
  $'// test-change: sum(0, 0) is flaky upstream, tracked in #12\ntest.skip(\'adds zero\', () => {')"

# The option gate: unset, the launcher never starts the hook.
out="$(payload Edit "$REPO/src/sum.test.ts" call-gate "$DROP_EXPECT" |
  CLAUDE_PLUGIN_OPTION_TEST_GUARDS_ENABLED='' node "$HOOK_DIR/exec-bash.mjs" \
    --require-true TEST_GUARDS_ENABLED "$HOOK" 2>&1)"
assert_empty "option unset: no output" "$out"

# (a) a removed expect( line is named, and the output carries no decision.
run Edit "$REPO/src/sum.test.ts" "$DROP_EXPECT"
if [[ $rc -eq 0 ]]; then ok "(a) exits 0"; else fail "(a) exit $rc"; fi
assert_contains "(a) goes back through additionalContext" "$out" '"additionalContext"'
assert_contains "(a) names the removed assertion" "$out" "expect(sum(2, 2)).toBe(4);"
assert_not_contains "(a) states the facts, gives no order" "$out" "Before you continue"
assert_no_decision "(a) no permissionDecision field while advisory" "$out"
if jq -e . <<<"$out" >/dev/null 2>&1; then ok "(a) one JSON document"; else fail "(a) not JSON: $out"; fi

# Advisory by default: an added skip gets context and no decision.
run Edit "$REPO/src/sum.test.ts" "$ADD_SKIP"
assert_contains "advisory: an added skip is named" "$out" "test.skip('adds zero'"
assert_contains "advisory: named as a skip" "$out" "skip"
assert_not_contains "advisory: it -> it.skip is not also called a removed test block" "$out" "removed 1 test block"
assert_no_decision "advisory: an added skip carries no decision" "$out"

# A suite skip (describe.skip, test.describe.skip) counts as an added skip.
printf "import { describe, it, expect } from 'vitest';\n\ndescribe('sum', () => {\n  it('adds', () => {\n    expect(1 + 1).toBe(2);\n  });\n});\n" >"$REPO/src/suite.test.ts"
run Edit "$REPO/src/suite.test.ts" "$(edit_input "describe('sum', () => {" "describe.skip('sum', () => {")"
assert_contains "suite skip: describe.skip is named as an added skip" "$out" "added 1 skip marker(s)"
printf "import { test, expect } from '@playwright/test';\n\ntest.describe('home', () => {\n  test('loads', async ({ page }) => {\n    await expect(page).toHaveTitle('Home');\n  });\n});\n" >"$REPO/src/home.spec.ts"
run Edit "$REPO/src/home.spec.ts" "$(edit_input "test.describe('home', () => {" "test.describe.skip('home', () => {")"
assert_contains "suite skip: test.describe.skip is named as an added skip" "$out" "added 1 skip marker(s)"

# (b) with rules.test-weaken-block: error, an added skip is denied, and the
# same edit carrying a test-change: marker gets context and no decision.
block_on
run Edit "$REPO/src/sum.test.ts" "$ADD_SKIP"
assert_deny "(b) block rule on: an added skip is denied" "$out"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$out")"
deny_tail="Denied: rules.test-weaken-block is error. If the change is deliberate, retry the edit with a test-change: <reason> comment naming why the test goes; otherwise fix the code, not the test."
if [[ "$reason" == "testing: sum.test.ts: this Edit weakens its tests:"$'\n'*$'\n'"$deny_tail" ]]; then
  ok "(b) the deny reason is the lead, the change, then the short directive"
else
  fail "(b) the deny reason is the lead, the change, then the short directive (got: $reason)"
fi
run Edit "$REPO/src/sum.test.ts" "$ADD_SKIP_MARKED"
assert_no_decision "(b) the marked edit has no decision" "$out"
assert_contains "(b) the marked edit still gets context" "$out" '"additionalContext"'

# Removed assertions and changed literals never deny, rule on or not (D4, D5).
run Edit "$REPO/src/sum.test.ts" "$DROP_EXPECT"
assert_no_decision "block rule on: a removed assertion is not denied" "$out"
assert_contains "block rule on: a removed assertion still gets context" "$out" "expect(sum(2, 2)).toBe(4);"
run Edit "$REPO/src/sum.test.ts" "$(edit_input '  expect(sum(1, 2)).toBe(3);' '  expect(sum(1, 2)).toBe(4);')"
assert_contains "a changed expected literal is named" "$out" "from 3 to 4"
assert_no_decision "block rule on: a changed literal is not denied" "$out"
# Comparison statements with one literal side: Go's `if got != 3 {` and a
# bats `[ "$output" = "3" ]`.
printf 'package sum\n\nimport "testing"\n\nfunc TestSum(t *testing.T) {\n\tgot := Sum(1, 2)\n\tif got != 3 {\n\t\tt.Errorf("got %%d", got)\n\t}\n}\n' >"$REPO/src/sum_test.go"
run Edit "$REPO/src/sum_test.go" "$(edit_input $'\tif got != 3 {' $'\tif got != 4 {')"
assert_contains "go-testing: a changed literal in an if comparison is named" "$out" "of got from 3 to 4"
# shellcheck disable=SC2016 # bats text, not expansions
printf '#!/usr/bin/env bats\n\n@test "sum" {\n  run ./sum 1 2\n  [ "$output" = "3" ]\n}\n' >"$REPO/src/sum.bats"
# shellcheck disable=SC2016 # bats text, not expansions
run Edit "$REPO/src/sum.bats" "$(edit_input '  [ "$output" = "3" ]' '  [ "$output" = "4" ]')"
assert_contains "bash-bats: a changed literal in a [ ] comparison is named" "$out" 'from \"3\" to \"4\"'
run Edit "$REPO/src/sum_test.go" "$(edit_input $'\tif got != 3 {' $'\tif got != 3 && ok {')"
assert_not_contains "go-testing: a compound condition is not read as a changed literal" "$out" "changed the expected"
# Seven changed literals: five are named, then one "..." line.
old7="" new7=""
for k in 1 2 3 4 5 6 7; do
  old7+="  expect(sum($k, 0)).toBe($k);"$'\n'
  new7+="  expect(sum($k, 0)).toBe($((k + 10)));"$'\n'
done
printf "import { test, expect } from 'vitest';\n\ntest('ids', () => {\n%s});\n" "$old7" >"$REPO/src/seven.test.ts"
run Edit "$REPO/src/seven.test.ts" "$(edit_input "$old7" "$new7")"
ctx7="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
if [[ "$(grep -c '^- changed the expected value of ' <<<"$ctx7")" == 5 ]]; then ok "changed literals: five named"; else fail "changed literals: five named (got: $ctx7)"; fi
assert_contains "changed literals: the rest elided" "$ctx7" $'\n- ...'
assert_not_contains "changed literals: the sixth is not named" "$ctx7" "sum(6, 0)"

# A removed test block is denied with the rule on.
run Write "$REPO/src/sum.test.ts" "$(jq -cn --arg c "$(sed '/^test(.adds zero/,$d' "$REPO/src/sum.test.ts")" '{content: $c}')"
assert_deny "block rule on: a Write that drops a test block is denied" "$out"
assert_contains "the deny reason names the removed test block" "$out" "adds zero"

# (c) a forced scanner error lets the edit through with no decision.
cat >"$TMP/broken.sh" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
run Edit "$REPO/src/sum.test.ts" "$ADD_SKIP" TEST_WEAKEN_SCANNER="$TMP/broken.sh"
if [[ $rc -eq 0 ]]; then ok "(c) scanner error exits 0"; else fail "(c) exit $rc"; fi
assert_no_decision "(c) scanner error: no decision" "$out"
assert_contains "(c) logs the error" "$(cat "$CLAUDE_PLUGIN_DATA/test-weaken.log" 2>/dev/null)" "scanner exited 3"

# (d) a hanging scanner hits the internal timeout and exits 0.
cat >"$TMP/hang.sh" <<'EOF'
#!/usr/bin/env bash
sleep 30
EOF
began=$SECONDS
run Edit "$REPO/src/sum.test.ts" "$ADD_SKIP" TEST_WEAKEN_SCANNER="$TMP/hang.sh" TEST_WEAKEN_TIMEOUT=1
if [[ $rc -eq 0 ]]; then ok "(d) timeout exits 0"; else fail "(d) exit $rc"; fi
if ((SECONDS - began < 5)); then ok "(d) returns before the hooks.json timeout"; else fail "(d) took $((SECONDS - began))s"; fi
assert_no_decision "(d) timeout: no decision" "$out"
assert_contains "(d) logs the timeout" "$(cat "$CLAUDE_PLUGIN_DATA/test-weaken.log" 2>/dev/null)" "timed out"
cat >"$TMP/spawn.sh" <<EOF
#!/usr/bin/env bash
sleep 30 &
echo \$! >"$TMP/child.pid"
wait
EOF
run Edit "$REPO/src/sum.test.ts" "$ADD_SKIP" TEST_WEAKEN_SCANNER="$TMP/spawn.sh" TEST_WEAKEN_TIMEOUT=1
sleep 0.2
if kill -0 "$(cat "$TMP/child.pid")" 2>/dev/null; then
  kill "$(cat "$TMP/child.pid")"
  fail "(d) a child the scanner spawned outlives the timeout"
else
  ok "(d) the timeout kills the scanner's children"
fi
# A scanner that exits 0 once its child is killed is still a timeout.
printf '#!/usr/bin/env bash\nsleep 30\nexit 0\n' >"$TMP/survive.sh"
: >"$CLAUDE_PLUGIN_DATA/test-weaken.log"
run Edit "$REPO/src/sum.test.ts" "$ADD_SKIP" TEST_WEAKEN_SCANNER="$TMP/survive.sh" TEST_WEAKEN_TIMEOUT=1
assert_no_decision "(d) a scanner that exits 0 after the timeout: no decision" "$out"
assert_contains "(d) and it logs the timeout" "$(cat "$CLAUDE_PLUGIN_DATA/test-weaken.log" 2>/dev/null)" "timed out"

# (d) with no CLAUDE_PLUGIN_DATA the log and markers stay out of TMPDIR.
mkdir -p "$TMP/tmpdir"
run Edit "$REPO/src/sum.test.ts" "$ADD_SKIP" TEST_WEAKEN_SCANNER="$TMP/broken.sh" \
  CLAUDE_PLUGIN_DATA= TMPDIR="$TMP/tmpdir" XDG_STATE_HOME="$TMP/state"
assert_empty "(d) no CLAUDE_PLUGIN_DATA writes nothing under TMPDIR" "$(ls -A "$TMP/tmpdir")"
assert_contains "(d) and logs under XDG_STATE_HOME" "$(cat "$TMP/state/claude-testing/test-weaken.log" 2>/dev/null)" "scanner exited 3"
block_off

# A pure addition, a new test with new assertions, is silent.
run Edit "$REPO/src/sum.test.ts" "$(edit_input '});' $'});\n\ntest(\'adds more\', () => {\n  expect(sum(3, 3)).toBe(6);\n});')"
assert_empty "a pure addition is silent" "$out"

# A Write that creates the file weakens nothing.
run Write "$REPO/src/new.test.ts" '{"content":"test(\"x\", () => {});"}'
assert_empty "a Write that creates a file is silent" "$out"

# A gitignored path and an excluded path are left alone.
run Edit "$REPO/scratch/ignored.test.ts" "$DROP_EXPECT"
assert_empty "a gitignored path is silent" "$out"
mkdir -p "$REPO/.claude"
printf "paths:\n  exclude: ['legacy/**']\n" >"$REPO/.claude/testing.yaml"
run Edit "$REPO/legacy/old.test.ts" "$DROP_EXPECT"
assert_empty "a paths.exclude path is silent" "$out"
block_off

# A fragment that cannot be lexed on its own says nothing.
run Edit "$REPO/src/sum.test.ts" "$(edit_input $'const s = `abc\n  expect(sum(2, 2)).toBe(4);' 'const s = `abc')"
assert_empty "an unjudgeable fragment is silent" "$out"

# Another adapter: a pytest skip decorator is named.
run Edit "$REPO/src/test_calc.py" "$(edit_input 'def test_add():' $'@pytest.mark.skip\ndef test_add():')"
assert_contains "pytest: an added skip decorator is named" "$out" "@pytest.mark.skip"

# Two overlapping `if` rows run the hook twice for one call; only one reports.
first="$(payload Edit "$REPO/src/sum.test.ts" dup-call "$DROP_EXPECT" | bash "$HOOK" 2>/dev/null)"
second="$(payload Edit "$REPO/src/sum.test.ts" dup-call "$DROP_EXPECT" | bash "$HOOK" 2>/dev/null)"
assert_contains "dedup: the first run for a tool_use_id reports" "$first" "expect(sum(2, 2))"
assert_empty "dedup: a second run for the same tool_use_id is silent" "$second"

# test-scan keeps its own marker: a call test-weaken saw still gets scanned.
printf 'test("x", () => {\n  run();\n});\n' >"$REPO/src/bare.test.ts"
out="$(jq -cn --arg f "$REPO/src/bare.test.ts" \
  '{hook_event_name: "PostToolUse", tool_name: "Write", session_id: "s1", tool_use_id: "dup-call",
    tool_input: {file_path: $f}, tool_response: {type: "create", structuredPatch: []}}' |
  bash "$HOOK_DIR/test-scan.sh" 2>/dev/null)"
assert_contains "test-scan still reports a call test-weaken already saw" "$out" "rule-zero-assertion"

echo
echo "$PASS passed, $FAIL failed"
((FAIL == 0))
