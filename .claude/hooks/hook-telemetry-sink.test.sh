#!/usr/bin/env bash
# Drift check: .claude/hooks/hook-telemetry-sink.sh is a copy of the claude-ops
# reference sink (plugins/claude-ops/hooks/hook-telemetry-sink.sh) that is
# byte-identical EXCEPT for the hook-utils.sh resolution block — the repo copy
# sources the repository's SSOT lib/hook-utils.sh because the plugin's sibling
# copy is not colocated here. This test fails when the two diverge anywhere
# else, so an upstream sink change without a re-copy is caught.
#
# Runner: scripts/run-plugin-tests.sh (once extended to .claude/hooks tests);
# also runnable directly: bash .claude/hooks/hook-telemetry-sink.test.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../.." && pwd)"

local_copy="$here/hook-telemetry-sink.sh"
upstream="$repo_root/plugins/claude-ops/hooks/hook-telemetry-sink.sh"

[[ -f "$local_copy" ]] || { echo "FAIL: missing $local_copy"; exit 1; }
[[ -f "$upstream" ]] || { echo "FAIL: missing $upstream"; exit 1; }

# Strip the resolution block from both: the shellcheck source directive, the
# source line itself, and the repo-copy-only comment lines that explain it.
strip_re='^# shellcheck source=|^source "\$\(dirname|^# Repo-local copy of the claude-ops reference sink|^# colocated here, so source the repository|^# the sibling pr-linkage-mcp-gate\.sh'

norm_upstream="$(mktemp)"
norm_local="$(mktemp)"
trap 'rm -f "$norm_upstream" "$norm_local"' EXIT
grep -v -E "$strip_re" "$upstream" >"$norm_upstream" || true
grep -v -E "$strip_re" "$local_copy" >"$norm_local" || true

if diff -u "$norm_upstream" "$norm_local" >/dev/null; then
  echo "PASS: repo-local telemetry sink matches the claude-ops reference sink (modulo the source block)"
else
  echo "FAIL: .claude/hooks/hook-telemetry-sink.sh has drifted from plugins/claude-ops/hooks/hook-telemetry-sink.sh"
  echo "Re-copy the reference sink and re-apply the lib/hook-utils.sh source repoint:"
  diff -u "$norm_upstream" "$norm_local" || true
  exit 1
fi

# The exclusion above is a prefix match, so it would also pass a copy whose
# source line points somewhere broken. Pin the exact expected target, then
# prove the wiring executes end-to-end: a valid envelope must append a record.
# shellcheck disable=SC2016  # deliberate: the literal source line is the fixture
expected_source='source "$(dirname "${BASH_SOURCE[0]}")/../../lib/hook-utils.sh"'
if ! grep -qF "$expected_source" "$local_copy"; then
  echo "FAIL: the repo copy's source line does not target ../../lib/hook-utils.sh"
  exit 1
fi

smoke_dir="$(mktemp -d)"
trap 'rm -f "$norm_upstream" "$norm_local"; rm -rf "$smoke_dir"' EXIT
printf '%s' '{"schema":"hook-telemetry/v1","hook":"drift-test-smoke","hook_event":"PreToolUse","duration_ms":1,"status":"ok","data":{"tool":"Bash","subject":"smoke"}}' \
  | CLAUDE_PROJECT_DIR="$smoke_dir" bash "$local_copy"
if [[ -s "$smoke_dir/.claude/observability/hook-events.jsonl" ]]; then
  echo "PASS: sink executes and appends a record (source target resolves)"
else
  echo "FAIL: sink ran but appended no record — source target or mapping broken"
  exit 1
fi
