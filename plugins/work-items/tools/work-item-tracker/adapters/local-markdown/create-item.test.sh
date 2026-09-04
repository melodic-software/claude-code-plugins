#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
# Foreign-provider edge id is well-formed by the shared grammar but rejected here
# (offline: fails before any storage access).
assert_usage_error "$S" --title x --parent "github:o/r#1"
assert_usage_error "$S" --title x --type # --type needs a value

# create-item is the verb that writes a whole item, so assert what reaches the
# store, not just the exit code. `type` is additive: supplied it round-trips,
# omitted it projects as JSON null rather than an empty string.
STORE="$(mktemp -d)"
TYPED="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title "typed item" --type bug)"
assert_eq "--type reaches the emitted record" "bug" "$(jq -r '.type' <<<"$TYPED")"
assert_contains "--type reaches the stored file" \
  "$(cat "$(jq -r '.url' <<<"$TYPED" | sed 's#^file://##')")" 'type: "bug"'
assert_eq "an item created without --type projects null" "null" \
  "$(WIT_STORAGE_DIR="$STORE" bash "$S" --title untyped | jq -r '.type')"

# A parent or blocker that does not exist is refused rather than persisted as a
# dead edge that get-item and the frontier would silently ignore.
WIT_STORAGE_DIR="$STORE" bash "$S" --title orphan --parent "local-markdown:local/markdown#999" >/dev/null 2>&1
assert_eq "a missing --parent is not-found (5), not a dead edge" "5" "$?"
WIT_STORAGE_DIR="$STORE" bash "$S" --title orphan --blocked-by "local-markdown:local/markdown#999" >/dev/null 2>&1
assert_eq "a missing --blocked-by is not-found (5), not a dead edge" "5" "$?"
rm -rf "$STORE"

[[ $FAILED -eq 0 ]] || exit 1
