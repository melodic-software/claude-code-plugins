#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/list-items.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" --state bogus
assert_usage_error "$S" --repo

# --repo is accepted for interface parity and re-targets nothing: the store is
# single-namespace, so a foreign --repo must still list the bound store rather
# than empty it or trip the unknown-argument path. The conformance binding never
# threads --repo (CB_REPO is empty for this adapter), so this is the only place
# the flag's parse is exercised.
STORE="$(mktemp -d)"
WIT_STORAGE_DIR="$STORE" bash "$(dirname "$S")/create-item.sh" --title "repo-parity" >/dev/null
LISTED="$(WIT_STORAGE_DIR="$STORE" bash "$S" --repo other/repo)"
assert_eq "--repo lists the bound store (exit 0)" "0" "$?"
assert_eq "--repo does not re-target the store" "1" "$(jq '.items | length' <<<"$LISTED")"
assert_eq "--repo leaves the stored namespace on the item" "local-markdown:local/markdown#1" \
  "$(jq -r '.items[0].id' <<<"$LISTED")"
rm -rf "$STORE"

[[ $FAILED -eq 0 ]] || exit 1
