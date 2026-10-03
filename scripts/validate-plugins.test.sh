#!/usr/bin/env bash
# Self-test for scripts/validate-plugins.sh's argument contract. The validation
# passes themselves need node and the claude CLI and run in CI's manifest step;
# what is pinned here is that a plugin list the script cannot honor is refused
# before anything runs, rather than narrowing the per-plugin pass to nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/validate-plugins.sh"
# shellcheck source=lib/test-harness.sh
. "$ROOT/scripts/lib/test-harness.sh"

expect_usage() {
  local label="$1" needle="$2" out rc=0
  shift 2
  out="$(bash "$SCRIPT" "$@" 2>&1)" || rc=$?
  if [[ "$rc" -eq 2 && "$out" == *"$needle"* ]]; then
    ok "$label"
  else
    fail "$label: expected exit 2 naming '$needle', got rc=$rc: $out"
  fi
}

expect_usage "an unknown flag is a usage error" "usage: validate-plugins.sh" --everything
expect_usage "--only without its list is a usage error" "usage: validate-plugins.sh" --only
expect_usage "--only with a stray second argument is a usage error" "usage: validate-plugins.sh" --only "guardrails" extra
expect_usage "a name that is not a plugin is refused" "'no-such-plugin' is not a plugin" --only "guardrails no-such-plugin"
expect_usage "a path in place of a name is refused" "is not a plugin" --only "../scripts"

test_harness::report
