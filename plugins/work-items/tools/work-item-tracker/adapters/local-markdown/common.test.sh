#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# common.sh is a sourceable contract lib — assert it sources cleanly, exposes its
# public helpers (no --help contract; it is sourced, never invoked), and that the
# pure-logic helpers behave. Full-verb behavior is covered offline by the
# local-markdown conformance binding.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../tests/lib.sh"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

for fn in wit_require_local_id wit_need_storage wit_item_file wit_next_number \
  wit_fm_field wit_fm_set wit_blocked_by_ids wit_lease_json wit_lease_is_live \
  wit_active_lease_json wit_next_lease_id wit_find_lease_file wit_emit_local_item \
  wit_help_if_requested; do
  if declare -F "$fn" >/dev/null; then
    pass "common.sh exposes $fn"
  else
    fail "common.sh exposes $fn" "declared" "missing"
  fi
done

assert_eq "lease marker constant" "<!-- work-item-lease v1 " "$WIT_LEASE_MARKER"
assert_eq "default namespace" "local/markdown" "$WIT_LOCAL_DEFAULT_NS"

# Foreign-provider IDs are rejected; local ones parse.
if wit_require_local_id "local-markdown:o/r#7"; then pass "accepts local id"; else fail "accepts local id" "0" "1"; fi
assert_eq "local id number parsed" "7" "$WIT_ID_NUMBER"
if wit_require_local_id "github:o/r#7"; then fail "rejects github id" "1" "0"; else pass "rejects github id"; fi

# Lease-time logic (wit_iso_to_epoch, wit_lease_is_live, wit_lease_json) is
# shared with the github adapter and tested once in lib/lease.test.sh.

# Storage-fixture helpers: build an item file with the exact write shape, then read back.
export WIT_STORAGE_DIR
WIT_STORAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$WIT_STORAGE_DIR"' EXIT
assert_eq "next number in empty store" "1" "$(wit_next_number)"
cat >"$WIT_STORAGE_DIR/1.md" <<'EOF'
---
id: "local-markdown:local/markdown#1"
number: 1
title: "hello, world: edge"
state: "open"
assignees: []
labels: ["a","b"]
parent: null
url: "file:///x/1.md"
---

Blocked by: local-markdown:local/markdown#2
EOF
assert_eq "fm_field reads json string with commas/colons" '"hello, world: edge"' "$(wit_fm_field "$WIT_STORAGE_DIR/1.md" title)"
assert_eq "fm_field reads array" '["a","b"]' "$(wit_fm_field "$WIT_STORAGE_DIR/1.md" labels)"
assert_eq "fm_field null parent" "null" "$(wit_fm_field "$WIT_STORAGE_DIR/1.md" parent)"
assert_eq "blocked-by parsed" "local-markdown:local/markdown#2" "$(wit_blocked_by_ids "$WIT_STORAGE_DIR/1.md")"
assert_eq "next number after one item" "2" "$(wit_next_number)"

wit_fm_set "$WIT_STORAGE_DIR/1.md" assignees '["me"]'
assert_eq "fm_set replaces in place" '["me"]' "$(wit_fm_field "$WIT_STORAGE_DIR/1.md" assignees)"
assert_eq "fm_set left title untouched" '"hello, world: edge"' "$(wit_fm_field "$WIT_STORAGE_DIR/1.md" title)"

[[ $FAILED -eq 0 ]] || exit 1
