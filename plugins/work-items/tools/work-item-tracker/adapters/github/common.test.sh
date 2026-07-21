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

# Bot-wrapper resolution (CONTRACT.md "Identity routing (GitHub adapter)"):
# consumer-local-first, plugin-bundled fallback, regardless of adapter location.
CONSUMER_ROOT="$(mktemp -d)"
mkdir -p "$CONSUMER_ROOT/tools/github-auth"
CONSUMER_WRAPPER="$CONSUMER_ROOT/tools/github-auth/gh-bot.sh"
: >"$CONSUMER_WRAPPER"
EMPTY_ROOT="$(mktemp -d)"
BUNDLED="$WIT_GH_ADAPTER_DIR/../../../github-auth/gh-bot.sh"

RESOLVED="$(CLAUDE_PROJECT_DIR="$CONSUMER_ROOT" wit_gh_resolve_bot_wrapper)"
if [[ "$RESOLVED" -ef "$CONSUMER_WRAPPER" ]]; then
  pass "resolves consumer-local wrapper first when present"
else
  fail "resolves consumer-local wrapper first when present" "$CONSUMER_WRAPPER" "$RESOLVED"
fi

RESOLVED_EMPTY_PROJECT="$(CLAUDE_PROJECT_DIR="$EMPTY_ROOT" wit_gh_resolve_bot_wrapper)"
assert_eq "falls back to bundled path when consumer has none" "$BUNDLED" "$RESOLVED_EMPTY_PROJECT"

RESOLVED_UNSET="$(unset CLAUDE_PROJECT_DIR; wit_gh_resolve_bot_wrapper)"
assert_eq "falls back to bundled path when CLAUDE_PROJECT_DIR unset" "$BUNDLED" "$RESOLVED_UNSET"

rm -rf "$CONSUMER_ROOT" "$EMPTY_ROOT"

[[ $FAILED -eq 0 ]] || exit 1
