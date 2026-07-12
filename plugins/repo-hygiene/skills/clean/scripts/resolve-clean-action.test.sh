#!/usr/bin/env bash
# Tests for resolve-clean-action.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"

RESOLVE="$SCRIPT_DIR/resolve-clean-action.sh"
FAILED=0

assert_action() {
  local label="$1" args="$2" want="$3"
  local out
  out="$(bash "$RESOLVE" $args)"
  assert_contains "$label" "$out" "Action: $want"
}

assert_action "empty -> menu" "" "menu"
assert_action "scan" "scan" "scan"
assert_action "inventory alias" "inventory" "scan"
assert_action "fresh alias" "fresh" "tree"
assert_action "fresh-pull alias" "fresh-pull" "tree"
assert_action "build alias" "artifacts" "build"
assert_action "git alias" "branches" "git"
assert_action "conflicting tokens -> menu" "scan tree" "menu"

if [[ $FAILED -ne 0 ]]; then
  echo "FAILED: $FAILED test(s)"
  exit 1
fi
echo "OK: resolve-clean-action.sh tests passed"
