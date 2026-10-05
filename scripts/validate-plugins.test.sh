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

# A contract warning fails the run (#6215), before any later pass runs. A
# stand-in `node` plays the contract validator: exit 0, one warning line.
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
printf '#!/usr/bin/env bash\necho "warning: plugins/x/.claude-plugin/plugin.json: probe" >&2\nexit 0\n' >"$TMP_ROOT/node"
chmod +x "$TMP_ROOT/node"
rc=0
out="$(PATH="$TMP_ROOT:$PATH" bash "$SCRIPT" --only "" 2>&1)" || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"warning: plugins/x/.claude-plugin/plugin.json: probe"* &&
  "$out" == *"printed a warning"* && "$out" != *"=== validate"* ]]; then
  ok "a contract warning fails the run and is printed"
else
  fail "a contract warning should fail the run with the warning shown, got rc=$rc: $out"
fi

test_harness::report
