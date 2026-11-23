#!/usr/bin/env bash

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/workflow-resilience-check.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

export CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED=true

workflow_script_json() { jq -nc --arg s "$1" '{tool_name:"Workflow",tool_input:{script:$s}}'; }
workflow_path_json() { jq -nc --arg p "$1" '{tool_name:"Workflow",tool_input:{scriptPath:$p}}'; }

run_hook() {
  local input="$1"
  shift
  env "$@" bash "$HOOK" <<<"$input" 2>&1
}

out=$(run_hook "$(workflow_script_json 'phase("x"); const r = await pipeline(FILES, s1, s2)')")
assert_contains "un-throttled pipeline warns" "$out" "no wave cap or retry wrapper"
assert_contains "names the throttle fix" "$out" "inWavesPipeline"
assert_contains "names the overloaded-retry ceiling" "$out" "CLAUDE_CODE_OVERLOADED_RETRY_MAX_DELAY_MS"
assert_contains "points at the retry docs section" "$out" "errors#tune-retry-behavior"

out=$(run_hook "$(workflow_script_json 'const r = await parallel(thunks)')")
assert_contains "un-throttled parallel warns" "$out" "no wave cap or retry wrapper"

out=$(run_hook "$(workflow_script_json 'const r = await inWaves(thunks, 5)')")
assert_silent "inWaves throttle suppresses warning" "$out"

out=$(run_hook "$(workflow_script_json 'const r = await inWavesPipeline(FILES, 4, s1, s2)')")
assert_silent "inWavesPipeline throttle suppresses warning" "$out"

out=$(run_hook "$(workflow_script_json 'const r = await parallel(items.map(i => () => agentRetry(p(i), {})))')")
assert_silent "agentRetry wrapper suppresses warning" "$out"

out=$(run_hook "$(workflow_script_json 'const a = await agent("do x"); const b = await agent("do y")')")
assert_silent "no fan-out stays silent" "$out"

out=$(run_hook "$(workflow_script_json 'await pipeline(FILES, s1)')" CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED=false)
assert_silent "kill switch silences hook" "$out"

out=$(env -u CLAUDE_PLUGIN_OPTION_WORKFLOW_RESILIENCE_CHECK_ENABLED \
  bash "$HOOK" <<<"$(workflow_script_json 'await pipeline(FILES, s1)')" 2>&1)
assert_silent "unset switch → no-op (advisory is opt-in by default)" "$out"

SAVED="$TEST_TMPDIR/engine.js"
printf 'export const meta = {}\nawait pipeline(FILES, s1, s2)\n' >"$SAVED"
out=$(run_hook "$(workflow_path_json "$SAVED")")
assert_contains "saved scriptPath is inspected" "$out" "no wave cap or retry wrapper"

out=$(printf '' | bash "$HOOK" 2>&1)
assert_silent "empty stdin is a no-op" "$out"

TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(workflow_script_json 'await pipeline(FILES, s1)')" >/dev/null 2>&1
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "workflow-resilience-check"
  assert_contains "telemetry: status ok (advisory never blocks)" "$(jq -r '.status' "$TEL")" "ok"
  assert_contains "telemetry: findings name the advisory" "$(jq -r '.data.findings[0] // empty' "$TEL")" \
    "no wave cap or retry wrapper"
else
  bad "telemetry envelope never appeared (advisory path)"
fi

TEL2="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK2="$(make_sink "cat >\"$TEL2\"")"
env HOOK_TELEMETRY_SINK="$SINK2" CLAUDE_PROJECT_DIR="$TEST_TMPDIR" \
  bash "$HOOK" <<<"$(workflow_script_json 'const a = await agent("do x")')" >/dev/null 2>&1
if wait_for_sink "$TEL2"; then
  assert_contains "telemetry: no-fan-out path also emits (meaningful outcome)" "$(jq -r '.status' "$TEL2")" "ok"
  assert_contains "telemetry: no-fan-out path has no findings" "$(jq -r '.data.findings | length' "$TEL2")" "0"
else
  bad "telemetry envelope never appeared (no-fan-out path)"
fi

report
