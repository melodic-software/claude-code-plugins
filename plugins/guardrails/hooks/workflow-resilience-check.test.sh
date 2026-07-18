#!/usr/bin/env bash
# Contract test for workflow-resilience-check.sh (guardrails plugin).
#
# Black-box: pipes PreToolUse Workflow JSON on stdin, asserts on the emitted
# additionalContext. The hook is advisory (always exit 0) — these cases verify
# WHEN it speaks (un-throttled fan-out) and WHEN it stays silent (throttled,
# no fan-out, kill switch). Self-contained — no host-repo assertion library.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/workflow-resilience-check.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# PreToolUse Workflow payload builders.
workflow_script_json() { jq -nc --arg s "$1" '{tool_name:"Workflow",tool_input:{script:$s}}'; }
workflow_path_json() { jq -nc --arg p "$1" '{tool_name:"Workflow",tool_input:{scriptPath:$p}}'; }

run_hook() {
  local input="$1"
  shift
  env "$@" bash "$HOOK" <<<"$input" 2>&1
}

# CASE 1: pipeline() fan-out, no throttle/retry → advisory fires.
out=$(run_hook "$(workflow_script_json 'phase("x"); const r = await pipeline(FILES, s1, s2)')")
assert_contains "un-throttled pipeline warns" "$out" "Workflow resilience"
assert_contains "names the throttle fix" "$out" "inWavesPipeline"

# CASE 2: parallel() fan-out, no throttle/retry → advisory fires.
out=$(run_hook "$(workflow_script_json 'const r = await parallel(thunks)')")
assert_contains "un-throttled parallel warns" "$out" "Workflow resilience"

# CASE 3: fan-out WITH inWaves → silent.
out=$(run_hook "$(workflow_script_json 'const r = await inWaves(thunks, 5)')")
assert_silent "inWaves throttle suppresses warning" "$out"

# CASE 4: pipeline WITH inWavesPipeline → silent.
out=$(run_hook "$(workflow_script_json 'const r = await inWavesPipeline(FILES, 4, s1, s2)')")
assert_silent "inWavesPipeline throttle suppresses warning" "$out"

# CASE 5: fan-out WITH agentRetry wrapper → silent.
out=$(run_hook "$(workflow_script_json 'const r = await parallel(items.map(i => () => agentRetry(p(i), {})))')")
assert_silent "agentRetry wrapper suppresses warning" "$out"

# CASE 6: no fan-out at all (single agent calls) → silent.
out=$(run_hook "$(workflow_script_json 'const a = await agent("do x"); const b = await agent("do y")')")
assert_silent "no fan-out stays silent" "$out"

# CASE 7: kill switch off → silent even on un-throttled fan-out.
out=$(run_hook "$(workflow_script_json 'await pipeline(FILES, s1)')" CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED=false)
assert_silent "kill switch silences hook" "$out"

# CASE 8: saved scriptPath with un-throttled fan-out → advisory fires (reads file).
SAVED="$TEST_TMPDIR/engine.js"
printf 'export const meta = {}\nawait pipeline(FILES, s1, s2)\n' >"$SAVED"
out=$(run_hook "$(workflow_path_json "$SAVED")")
assert_contains "saved scriptPath is inspected" "$out" "Workflow resilience"

# CASE 9: empty stdin → silent (graceful no-op).
out=$(printf '' | bash "$HOOK" 2>&1)
assert_silent "empty stdin is a no-op" "$out"

report
