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
#
# Skips are never silent: the summary names every suite that skipped and why,
# so "exit 0 with skips" reads differently from "all green" (#1313 — a suite
# whose only coverage skipped used to be indistinguishable from a pass).
# --strict-skips turns any optional SKIP into a failure, for callers that have
# provisioned the full toolchain and want a skip to mean the environment
# regressed rather than that a tool is optional.
set -uo pipefail

# Fixture isolation (#2840). git exports GIT_DIR/GIT_WORK_TREE into every hook
# it invokes, and `git config`'s default --local scope follows GIT_DIR ahead of
# both `-C` and the working directory. A suite spawned with those inherited
# writes its throwaway fixture identity into the CALLER's .git/config — shared
# by every worktree of the clone — instead of into its fixture. Clearing them
# once here isolates every suite this runner spawns, whatever idiom that suite
# uses internally.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_PREFIX GIT_OBJECT_DIRECTORY

strict_skips=0
if [[ "${1:-}" == "--strict-skips" ]]; then
  strict_skips=1
  shift
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

mapfile -t tests < <(find plugins .claude/hooks -type f -name '*.test.sh' 2>/dev/null | sort)

if [[ ${#tests[@]} -eq 0 ]]; then
  echo "error: no plugin tests found under plugins/**/*.test.sh" >&2
  exit 2
fi

failed=0
total_optional_skips=0
total_discriminating_skips=0
skipped_suites=()

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
  if ((opt_skips > 0)); then
    first_reason="$(grep -m1 '^SKIP:' "$log")"
    skipped_suites+=("$t — ${opt_skips} SKIP(s), first: ${first_reason#SKIP: }")
  fi
  if ((disc_skips > 0)); then
    echo "DISCRIMINATING SKIP: $t vacated $disc_skips discriminating case(s)" >&2
  fi
  rm -f "$log"
done

echo ""
echo "Plugin test aggregate: ${total_optional_skips} optional SKIP(s), ${total_discriminating_skips} DISCRIMINATING SKIP(s)."
if ((${#skipped_suites[@]} > 0)); then
  echo "Suites with skipped coverage (exit 0 here is NOT evidence those cases ran):"
  for s in "${skipped_suites[@]}"; do
    echo "  SKIPPED: $s"
  done
fi

if ((total_discriminating_skips > 0)); then
  {
    echo "DISCRIMINATING SKIP(s) mean discriminating coverage did not run —"
    echo "this run is not equivalent to a full pass."
  } >&2
  failed=1
fi

if ((strict_skips)) && ((total_optional_skips > 0)); then
  {
    echo "--strict-skips: ${total_optional_skips} optional SKIP(s) occurred in an"
    echo "environment declared to have the full toolchain — treating as failure."
  } >&2
  failed=1
fi

if [[ $failed -ne 0 ]]; then
  echo "One or more plugin tests failed." >&2
  exit 1
fi
if ((total_optional_skips > 0)); then
  echo "All executed plugin tests passed; ${total_optional_skips} case(s) skipped (named above)."
else
  echo "All plugin tests passed."
fi
