#!/usr/bin/env bash
# test-scope: plugins/work-items/tools/work-item-tracker/adapters/local-markdown/*
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACKER="$SCRIPT_DIR/../../work-item-tracker.sh"
source "$SCRIPT_DIR/../../tests/lib.sh"

STORAGE="$(mktemp -d)"
BINDING_DIR="$(mktemp -d)"
BINDING="$BINDING_DIR/binding.json"
jq -cn --arg dir "$STORAGE" \
  '{schema_version: "1.0", provider: "local-markdown", config: {lease_ttl_hours: 24, storage_dir: $dir}}' \
  >"$BINDING"
export WORK_ITEM_TRACKER_BINDING="$BINDING"
cleanup() {
  rm -rf "$STORAGE" "${STORAGE_REAL:-}"
  rm -rf "$BINDING_DIR"
}
trap cleanup EXIT

assert_eq "binding sits in a private dir, not the shared TMPDIR" \
  "no" "$([[ "$(dirname "$BINDING")" == "${TMPDIR:-/tmp}" ]] && echo yes || echo no)"

new() { bash "$TRACKER" create-item "$@" | jq -r '.id'; }

# A container (spec-container) with two direct children, an unrelated leaf, and a
# grandchild (proves enumeration is DIRECT children only). Capture C2's full
# record to recover the store's on-disk path from its own reported url — the
# tracker resolves the storage dir itself (and MSYS may translate it), so never
# assume the outer $STORAGE is where files land.
MAP="$(new --title map --labels spec-container)"
C1="$(new --title c1 --parent "$MAP")"
C2_JSON="$(bash "$TRACKER" create-item --title c2 --parent "$MAP")"
C2="$(jq -r '.id' <<<"$C2_JSON")"
C2_FILE="$(jq -r '.url' <<<"$C2_JSON" | sed 's#^file://##')"
STORAGE_REAL="$(dirname "$C2_FILE")"
LEAF="$(new --title unrelated)"
GC="$(new --title grandchild --parent "$C1")"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"
wit_fm_set "$C2_FILE" state '"closed"'

ALL="$(bash "$TRACKER" list-sub-items "$MAP" | jq -c '[.items[].id]')"
assert_contains "list-sub-items holds open child C1" "$ALL" "$C1"
assert_contains "list-sub-items holds closed child C2" "$ALL" "$C2"
assert_not_contains "list-sub-items excludes the container itself" "$ALL" "$MAP"
assert_not_contains "list-sub-items excludes an unrelated leaf" "$ALL" "$LEAF"
assert_not_contains "list-sub-items excludes a grandchild (direct children only)" "$ALL" "$GC"
assert_eq "list-sub-items (default all) child count" "2" "$(bash "$TRACKER" list-sub-items "$MAP" | jq '.items | length')"
assert_eq "children carry parent_id" "$MAP $MAP" \
  "$(bash "$TRACKER" list-sub-items "$MAP" | jq -r '[.items[].parent_id] | join(" ")')"

assert_eq "list-sub-items --state open keeps only C1" "$C1" \
  "$(bash "$TRACKER" list-sub-items "$MAP" --state open | jq -r '[.items[].id] | join(",")')"
assert_eq "list-sub-items --state closed keeps only C2" "$C2" \
  "$(bash "$TRACKER" list-sub-items "$MAP" --state closed | jq -r '[.items[].id] | join(",")')"

assert_eq "list-sub-items on a leaf is empty" "0" \
  "$(bash "$TRACKER" list-sub-items "$LEAF" | jq '.items | length')"

PFRONT="$(bash "$TRACKER" list-frontier --parent "$MAP" | jq -c '[.items[].id]')"
assert_contains "scoped frontier holds the open child C1" "$PFRONT" "$C1"
assert_not_contains "scoped frontier drops the closed child C2" "$PFRONT" "$C2"
assert_not_contains "scoped frontier drops the grandchild (not a direct child)" "$PFRONT" "$GC"
assert_not_contains "scoped frontier never holds the container" "$PFRONT" "$MAP"

GFRONT="$(bash "$TRACKER" list-frontier | jq -c '[.items[].id]')"
assert_not_contains "global frontier excludes the unassigned/unblocked container" "$GFRONT" "$MAP"
assert_contains "global frontier still holds the workable leaf" "$GFRONT" "$LEAF"

[[ $FAILED -eq 0 ]] || exit 1
