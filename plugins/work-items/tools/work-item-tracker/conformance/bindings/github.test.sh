#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# github.sh is a sourceable conformance binding — assert it sources cleanly and
# exposes the cb_setup/cb_teardown contract without touching the network.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/lib.sh"
# shellcheck source=github.sh
source "$SCRIPT_DIR/github.sh"

for fn in cb_setup cb_teardown; do
  if declare -F "$fn" >/dev/null; then
    pass "github binding exposes $fn"
  else
    fail "github binding exposes $fn" "declared" "missing"
  fi
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
