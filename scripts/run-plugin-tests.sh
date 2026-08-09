#!/usr/bin/env bash
# Run every plugin contract test (plugins/**/*.test.sh) plus the repo-local
# hook tests (.claude/hooks/*.test.sh) and fail if any fails. The repo-local
# hooks are tracked policy with the same test conventions as plugin hooks;
# before this runner covered them, .claude/hooks/pr-linkage-mcp-gate.test.sh
# never ran in CI and the copy drifted silently from its plugin sibling.
#
# Each test is self-contained and cwd-independent; an individual test SKIPs
# (exit 0) when an optional tool it needs (shellcheck, shfmt, ...) is absent, so
# this runner gates on real failures without requiring every tool to be present.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

mapfile -t tests < <(find plugins .claude/hooks -type f -name '*.test.sh' 2>/dev/null | sort)

if [[ ${#tests[@]} -eq 0 ]]; then
  echo "error: no plugin tests found under plugins/**/*.test.sh" >&2
  exit 2
fi

failed=0
for t in "${tests[@]}"; do
  echo "=== $t ==="
  if bash "$t"; then
    echo "PASS: $t"
  else
    echo "FAIL: $t" >&2
    failed=1
  fi
done

if [[ $failed -ne 0 ]]; then
  echo "One or more plugin tests failed." >&2
  exit 1
fi
echo "All plugin tests passed or were skipped."
