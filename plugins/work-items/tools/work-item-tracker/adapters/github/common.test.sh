#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# common.sh is a sourceable contract lib — assert it sources cleanly and exposes
# its public helpers (no --help contract; it is sourced, never invoked).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/lib.sh"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

for fn in gh_write wit_run_gh wit_resolve_repo wit_emit_item wit_lease_json \
  wit_lease_is_live wit_list_lease_comments wit_help_if_requested wit_map_gh_error; do
  if declare -F "$fn" >/dev/null; then
    pass "common.sh exposes $fn"
  else
    fail "common.sh exposes $fn" "declared" "missing"
  fi
done

assert_eq "lease marker constant" "<!-- work-item-lease v1 " "$WIT_LEASE_MARKER"

# Lease-time logic (wit_iso_to_epoch, wit_lease_is_live, wit_lease_json) is
# shared with the local-markdown adapter and tested once in lib/lease.test.sh.

# Error mapping is pure — spot-check the classifier.
assert_eq "404 → not-found (5)" "5" "$(wit_map_gh_error 'HTTP 404 Not Found')"
assert_eq "rate limit → unavailable (8)" "8" "$(wit_map_gh_error 'API rate limit exceeded')"

[[ $FAILED -eq 0 ]] || exit 1
