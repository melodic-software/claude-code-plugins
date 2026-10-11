#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
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
STORE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
WIT_STORAGE_DIR="$STORE" bash "$(dirname "$S")/create-item.sh" --title "repo-parity" >/dev/null
LISTED="$(WIT_STORAGE_DIR="$STORE" bash "$S" --repo other/repo)"
assert_eq "--repo lists the bound store (exit 0)" "0" "$?"
assert_eq "--repo does not re-target the store" "1" "$(jq '.items | length' <<<"$LISTED")"
assert_eq "--repo leaves the stored namespace on the item" "local-markdown:local/markdown#1" \
  "$(jq -r '.items[0].id' <<<"$LISTED")"
rm -rf "$STORE"

# --- the envelope reports truncation at the declared ceiling ---
# A fixture copy of the adapter declares a ceiling of 2. `truncated` turns on a
# MATCHING item past the ceiling: a closed item there leaves an open listing complete.
FIX="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
mkdir -p "$FIX/adapters"
cp -R "$(dirname "$S")" "$FIX/adapters/local-markdown"
cp -R "$(dirname "$S")/../../lib" "$FIX/lib"
jq '.limits.list_items_max = 2' "$(dirname "$S")/capabilities.json" >"$FIX/adapters/local-markdown/capabilities.json"
FS="$FIX/adapters/local-markdown/list-items.sh"
STORE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
for t in one two; do
  WIT_STORAGE_DIR="$STORE" bash "$(dirname "$S")/create-item.sh" --title "$t" >/dev/null
done
LISTED="$(WIT_STORAGE_DIR="$STORE" bash "$FS")"
assert_eq "exactly the ceiling's worth of open items: truncated is false" "false" "$(jq -c '.truncated' <<<"$LISTED")"
WIT_STORAGE_DIR="$STORE" bash "$(dirname "$S")/create-item.sh" --title "closed" >/dev/null
sed 's/^state: "open"$/state: "closed"/' "$STORE/3.md" >"$STORE/3.md.new" && mv "$STORE/3.md.new" "$STORE/3.md"
LISTED="$(WIT_STORAGE_DIR="$STORE" bash "$FS")"
assert_eq "a closed item past the ceiling: the open listing is complete" "false" "$(jq -c '.truncated' <<<"$LISTED")"
WIT_STORAGE_DIR="$STORE" bash "$(dirname "$S")/create-item.sh" --title "three" >/dev/null
LISTED="$(WIT_STORAGE_DIR="$STORE" bash "$FS")"
assert_eq "an open item past the ceiling: truncated is true" "true" "$(jq -c '.truncated' <<<"$LISTED")"
assert_eq "past the ceiling: only the ceiling's worth of items" "2" "$(jq '.items | length' <<<"$LISTED")"
LISTED="$(WIT_STORAGE_DIR="$STORE" bash "$FS" --state closed)"
assert_eq "one closed item, under the ceiling: the closed listing is complete" "false" "$(jq -c '.truncated' <<<"$LISTED")"

# --- --label filters before the ceiling counts (#7173) ---
# Three open items already fill past the ceiling of 2; one more carries the label. The
# labeled listing holds that one item and is complete.
WIT_STORAGE_DIR="$STORE" bash "$(dirname "$S")/create-item.sh" --title "labeled" --labels "area: ci" >/dev/null
LISTED="$(WIT_STORAGE_DIR="$STORE" bash "$FS" --label "area: ci")"
assert_eq "--label past an unlabeled ceiling → exit 0" "0" "$?"
assert_eq "--label lists the labeled item only" "local-markdown:local/markdown#5" "$(jq -r '[.items[].id] | join(",")' <<<"$LISTED")"
assert_eq "--label listing under the ceiling is complete" "false" "$(jq -c '.truncated' <<<"$LISTED")"
LISTED="$(WIT_STORAGE_DIR="$STORE" bash "$FS" --label "area")"
assert_eq "--label matches whole label names, not substrings" "0" "$(jq '.items | length' <<<"$LISTED")"
assert_usage_error "$S" --label

# --- created_at: written at create, null for an item written before the field ---
assert_eq "a created item carries a UTC created_at" "true" \
  "$(jq -r '.items[0].created_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' <<<"$(WIT_STORAGE_DIR="$STORE" bash "$FS" --label "area: ci")")"
grep -v '^created_at: ' "$STORE/5.md" >"$STORE/5.md.old"
mv "$STORE/5.md.old" "$STORE/5.md"
assert_eq "an item without the field reads created_at null" "null" \
  "$(jq -c '.items[0].created_at' <<<"$(WIT_STORAGE_DIR="$STORE" bash "$FS" --label "area: ci")")"

[[ $FAILED -eq 0 ]] || exit 1
