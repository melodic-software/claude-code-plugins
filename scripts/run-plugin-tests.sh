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
total_optional_skips=0
total_discriminating_skips=0

if command -v git >/dev/null 2>&1; then
  echo "Runner git: $(git --version)"
else
  echo "Runner git: unavailable"
fi

for t in "${tests[@]}"; do
  echo "=== $t ==="
  log="$(mktemp)"
  if bash "$t" 2>&1 | tee "$log"; then
    echo "PASS: $t"
  else
    echo "FAIL: $t" >&2
    failed=1
  fi
  opt_skips="$(grep -c '^SKIP:' "$log" 2>/dev/null || true)"
  disc_skips="$(grep -c '^DISCRIMINATING SKIP:' "$log" 2>/dev/null || true)"
  total_optional_skips=$((total_optional_skips + opt_skips))
  total_discriminating_skips=$((total_discriminating_skips + disc_skips))
  if ((disc_skips > 0)); then
    echo "DISCRIMINATING SKIP: $t vacated $disc_skips discriminating case(s)" >&2
  fi
  rm -f "$log"
done

echo ""
echo "Plugin test aggregate: ${total_optional_skips} optional SKIP(s), ${total_discriminating_skips} DISCRIMINATING SKIP(s)."

if ((total_discriminating_skips > 0)); then
  {
    echo "DISCRIMINATING SKIP(s) mean discriminating coverage did not run —"
    echo "this run is not equivalent to a full pass."
  } >&2
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  echo "One or more plugin tests failed." >&2
  exit 1
fi
echo "All plugin tests passed or were skipped."
