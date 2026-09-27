#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# RUNS the full abstract suite against the consume-only jira adapter, once normally and
# once under a PATH shim that makes gh/curl fail: every exercised path is pre-network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../run-conformance.sh"
source "$SCRIPT_DIR/../../tests/lib.sh"

CB_REPO=""
# shellcheck source=jira.sh
source "$SCRIPT_DIR/jira.sh"
for fn in cb_setup cb_teardown; do
  assert_succeeds "jira binding exposes $fn" "declared" "missing" declare -F "$fn"
done
assert_eq "consume-only binding leaves CB_REPO empty" "" "$CB_REPO"

# Full suite, exit 0.
bash "$RUNNER" --binding jira >/dev/null 2>&1
assert_eq "conformance --binding jira exit 0" "0" "$?"

# Zero-network: a PATH shim makes gh + curl exit 1 and the suite must still pass
# (no unshare -n on Git Bash).
SHIM="$(mktemp -d)"
write_blocking_network_shim "$SHIM"
PATH="$SHIM:$PATH" bash "$RUNNER" --binding jira >/dev/null 2>&1
assert_eq "conformance --binding jira exit 0 under gh/curl-blocking shim" "0" "$?"
rm -rf "$SHIM"

[[ $FAILED -eq 0 ]] || exit 1
