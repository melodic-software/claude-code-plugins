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
normalize() {
  grep -v -E '^# shellcheck source=|^source "\$\(dirname|^# Repo-local copy of the claude-ops reference sink|^# colocated here, so source the repository|^# the sibling pr-linkage-mcp-gate\.sh' "$1"
}

if diff -u <(normalize "$upstream") <(normalize "$local_copy") >/dev/null; then
  echo "PASS: repo-local telemetry sink matches the claude-ops reference sink (modulo the source block)"
else
  echo "FAIL: .claude/hooks/hook-telemetry-sink.sh has drifted from plugins/claude-ops/hooks/hook-telemetry-sink.sh"
  echo "Re-copy the reference sink and re-apply the lib/hook-utils.sh source repoint:"
  diff -u <(normalize "$upstream") <(normalize "$local_copy") || true
  exit 1
fi
