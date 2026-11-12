#!/usr/bin/env bash
# .claude/hooks/hook-telemetry-sink.sh is a shim that sources the harness-ops
# reference sink (plugins/harness-ops/hooks/hook-telemetry-sink.sh). Pin its
# target, then prove the wiring executes end-to-end: a valid envelope must
# append a record.
#
# Runner: scripts/run-plugin-tests.sh (once extended to .claude/hooks tests);
# also runnable directly: bash .claude/hooks/hook-telemetry-sink.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shim="$here/hook-telemetry-sink.sh"

[[ -f "$shim" ]] || {
  echo "FAIL: missing $shim"
  exit 1
}

# shellcheck disable=SC2016  # deliberate: the literal source line is the fixture
expected_source='source "$HOOK_DIR/../../plugins/harness-ops/hooks/hook-telemetry-sink.sh"'
if ! grep -qF "$expected_source" "$shim"; then
  echo "FAIL: the shim's source line does not target the harness-ops sink"
  exit 1
fi

smoke_dir="$(mktemp -d)"
trap 'rm -rf "$smoke_dir"' EXIT
printf '%s' '{"schema":"hook-telemetry/v1","hook":"drift-test-smoke","hook_event":"PreToolUse","duration_ms":1,"status":"ok","data":{"tool":"Bash","subject":"smoke"}}' |
  CLAUDE_PROJECT_DIR="$smoke_dir" bash "$shim"
if [[ -s "$smoke_dir/.observability/claude/hook-events.jsonl" ]]; then
  echo "PASS: sink executes and appends a record (source target resolves)"
else
  echo "FAIL: sink ran but appended no record — source target or mapping broken"
  exit 1
fi
