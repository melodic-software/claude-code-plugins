#!/usr/bin/env bash
# Contract tests for tools/grok-build/grok-availability.mjs and its
# check-availability.sh wrapper. Availability is a report, not a gate — the
# probe must always exit 0 and emit a single-line JSON object whose shape is
# stable regardless of whether Grok is installed/authenticated on this host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
# shellcheck source=../../tests/shell/lib.sh
source "$REPO_ROOT/tests/shell/lib.sh"

FAILED=0
CASE_NUM=0

PROBE="$SCRIPT_DIR/grok-availability.mjs"
WRAPPER="$SCRIPT_DIR/check-availability.sh"

assert_file_exists "grok-availability.mjs exists" "$PROBE"
assert_file_exists "check-availability.sh exists" "$WRAPPER"

# Direct probe: exit 0 + stable JSON keys present in every branch.
set +e
probe_out="$(node "$PROBE")"
probe_code=$?
set -e
assert_exit "probe exits 0" 0 "$probe_code"
for key in '"available":' '"ready":' '"reason":' '"auth_present":' '"version":' '"doc":"docs/grok-build/README.md"'; do
  assert_contains "probe JSON has $key" "$probe_out" "$key"
done

# Wrapper delegates to the probe and yields the same contract.
set +e
wrapper_out="$(bash "$WRAPPER")"
wrapper_code=$?
set -e
assert_exit "check-availability.sh exits 0" 0 "$wrapper_code"
assert_contains "wrapper JSON has available key" "$wrapper_out" '"available":'

[[ $FAILED -eq 0 ]] || exit 1
