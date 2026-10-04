#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced lib
# common.sh is a sourceable contract lib — assert it sources cleanly, exposes its
# public helpers (no --help contract; it is sourced, never invoked), and that the
# pure-logic helpers behave. Full-verb behavior is covered offline by the
# local-markdown conformance binding.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../tests/lib.sh"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

for fn in wit_require_local_id wit_need_storage wit_item_file wit_next_number \
  wit_fm_field wit_fm_set wit_blocked_by_ids wit_lease_json wit_lease_is_live \
  wit_active_lease_json wit_next_lease_id wit_find_lease_file wit_emit_local_item \
  wit_help_if_requested; do
  assert_succeeds "common.sh exposes $fn" "declared" "missing" declare -F "$fn"
done

assert_eq "lease marker constant" "<!-- work-item-lease v1 " "$WIT_LEASE_MARKER"
assert_eq "default namespace" "local/markdown" "$WIT_LOCAL_DEFAULT_NS"

# Foreign-provider IDs are rejected; local ones parse.
assert_succeeds "accepts local id" "0" "1" wit_require_local_id "local-markdown:o/r#7"
assert_eq "local id number parsed" "7" "$WIT_ID_NUMBER"
assert_fails "rejects github id" "1" "0" wit_require_local_id "github:o/r#7"

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

# The store walk and the next-number allocation share one file-name filter, so
# pin both against a gap and a non-item file: numbers are max+1 rather than
# count+1, and a markdown file that is not an item never enters either answer.
#
# The fixture is 2 and 10 on purpose. Allocation derives the maximum from the
# tail of this walk, so the walk's NUMERIC ordering is load-bearing: under a
# lexical sort these come back "1,10,2," and the next number is 3, which is an
# existing item. The pair must straddle a digit-count boundary to discriminate,
# and it must not be {1,10}, whose lexical and numeric orders agree.
touch "$WIT_STORAGE_DIR/2.md" "$WIT_STORAGE_DIR/10.md" "$WIT_STORAGE_DIR/notes.md"
assert_eq "item numbers ascend and skip non-numeric names" "1,2,10," "$(wit_item_numbers | tr '\n' ',')"
assert_eq "next number is max+1 across a gap" "11" "$(wit_next_number)"
rm -f "$WIT_STORAGE_DIR/notes.md"

wit_fm_set "$WIT_STORAGE_DIR/1.md" assignees '["me"]'
assert_eq "fm_set replaces in place" '["me"]' "$(wit_fm_field "$WIT_STORAGE_DIR/1.md" assignees)"
assert_eq "fm_set left title untouched" '"hello, world: edge"' "$(wit_fm_field "$WIT_STORAGE_DIR/1.md" title)"

# A closed blocker unblocks only when it was completed. `state_reason` is this
# format's close reason; a closed item without one was completed.
# blocker_item <number> <state> [<state_reason>] / dependent_of <number> <blocker>.
blocker_item() {
  printf -- '---\nid: "local-markdown:local/markdown#%s"\nnumber: %s\ntitle: "b"\nstate: "%s"\n%bassignees: []\nlabels: []\nparent: null\nurl: "file:///x"\n---\n' \
    "$1" "$1" "$2" "${3:+state_reason: \"$3\"\n}" >"$WIT_STORAGE_DIR/$1.md"
}
dependent_of() {
  blocker_item "$1" open
  printf '\nBlocked by: local-markdown:local/markdown#%s\n' "$2" >>"$WIT_STORAGE_DIR/$1.md"
}
blocker_item 41 open
blocker_item 42 closed
blocker_item 43 closed completed
blocker_item 44 closed not_planned
blocker_item 45 closed duplicate
for n in 41 42 43 44 45; do dependent_of "$((n + 10))" "$n"; done
counts() { wit_emit_local_item "$1" | jq -r '"\(.blocked_by_count) \(.blocked_by_wont_do_count)"'; }
assert_eq "OPEN blocker blocks, not won't-do" "1 0" "$(counts 51)"
assert_eq "closed blocker without a reason was completed: unblocks" "0 0" "$(counts 52)"
assert_eq "closed completed blocker unblocks" "0 0" "$(counts 53)"
assert_eq "closed not_planned blocker blocks and counts as won't-do" "1 1" "$(counts 54)"
assert_eq "closed duplicate blocker blocks and counts as won't-do" "1 1" "$(counts 55)"

[[ $FAILED -eq 0 ]] || exit 1
