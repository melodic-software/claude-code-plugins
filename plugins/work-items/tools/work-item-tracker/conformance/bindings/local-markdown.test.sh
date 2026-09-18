#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# Wires the local-markdown conformance run into shell-test discovery (offline,
# in-CI). Unlike the GitHub binding test (which only source-checks the binding
# because its suite is on-demand against a sandbox), this RUNS the full abstract
# conformance suite through the core CLI against the local-markdown adapter — once
# normally, once under a PATH shim that makes gh/curl fail, proving the offline
# reference path touches no network tool.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../run-conformance.sh"
source "$SCRIPT_DIR/../../tests/lib.sh"

# Binding sources cleanly and exposes the cb_setup/cb_teardown contract. The runner
# defaults CB_REPO="" before sourcing a binding; mirror that so the assertion below
# tests that this binding leaves it untouched (single-namespace store, no --repo).
CB_REPO=""
# shellcheck source=local-markdown.sh
source "$SCRIPT_DIR/local-markdown.sh"
for fn in cb_setup cb_teardown; do
  assert_succeeds "local-markdown binding exposes $fn" "declared" "missing" declare -F "$fn"
done
assert_eq "single-namespace binding leaves CB_REPO empty" "" "$CB_REPO"

# Full suite, exit 0.
bash "$RUNNER" --binding local-markdown >/dev/null 2>&1
assert_eq "conformance --binding local-markdown exit 0" "0" "$?"

# Zero-network: a PATH shim makes gh + curl exit 1; the suite must still pass,
# proving the adapter never reaches for a network tool (no unshare -n on Git Bash).
SHIM="$(mktemp -d)"
write_blocking_network_shim "$SHIM"
PATH="$SHIM:$PATH" bash "$RUNNER" --binding local-markdown >/dev/null 2>&1
assert_eq "conformance --binding local-markdown exit 0 under gh/curl-blocking shim" "0" "$?"
rm -rf "$SHIM"

[[ $FAILED -eq 0 ]] || exit 1
