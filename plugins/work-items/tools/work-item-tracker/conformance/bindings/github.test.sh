#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# github.sh is a sourceable conformance binding — assert it sources cleanly and
# exposes the cb_setup/cb_teardown contract without touching the network.
#
# It does NOT run the suite: that mutates real sandbox issues, so github stays an
# on-demand binding run by hand.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"
# shellcheck source=github.sh
source "$SCRIPT_DIR/github.sh"

for fn in cb_setup cb_teardown; do
  assert_succeeds "github binding exposes $fn" "declared" "missing" declare -F "$fn"
done

# No retained default: cb_setup refuses when the target is unset (the guard fires
# before any network call, so this stays offline).
if (
  unset WIT_CONFORMANCE_GITHUB_REPO
  cb_setup
) 2>/dev/null; then
  fail "cb_setup requires explicit target" "nonzero exit" "succeeded"
else
  pass "cb_setup requires explicit target (no retained default)"
fi

[[ $FAILED -eq 0 ]] || exit 1
