#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/add-recurrence.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

LINK="https://github.com/o/r/actions/runs/1"
assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" "local-markdown:local/markdown#1" --note seen       # no --source-link
assert_usage_error "$S" "local-markdown:local/markdown#1" --source-link "$LINK" # no --note
assert_usage_error "$S" "local-markdown:local/markdown#1" --source-link "$LINK" --note ""
assert_usage_error "$S" "local-markdown:local/markdown#1" --source-link "not a url" --note seen
assert_usage_error "$S" "github:o/r#1" --source-link "$LINK" --note seen

command -v jq >/dev/null 2>&1 || skip_suite "jq not on PATH"

ADAPTER="$(dirname "$S")"
STORE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
ITEM="$(WIT_STORAGE_DIR="$STORE" bash "$ADAPTER/create-item.sh" --title "recurring signal")"
ITEM_ID="$(jq -r '.id' <<<"$ITEM")"
ITEM_FILE="$(jq -r '.url' <<<"$ITEM" | sed 's#^file://##')"

run() {
  OUT="$(WIT_STORAGE_DIR="$STORE" bash "$S" "$@" 2>"$TMP_ROOT/err")"
  RC=$?
}

run "$ITEM_ID" --source-link "$LINK" --note "seen on run 1"
assert_eq "first sighting → exit 0" "0" "$RC"
assert_eq "first sighting is recorded" "true" "$(jq -r '.recorded' <<<"$OUT")"
assert_eq "result carries the item id" "$ITEM_ID" "$(jq -r '.id' <<<"$OUT")"
assert_eq "result carries the source link" "$LINK" "$(jq -r '.source_link' <<<"$OUT")"
STORED="$(grep -F 'work-item-recurrence' "$ITEM_FILE")"
assert_contains "the stored marker carries the link" "$STORED" "\"source_link\":\"$LINK\""
assert_contains "the stored marker carries the note" "$STORED" '"note":"seen on run 1"'

BEFORE="$(cat "$ITEM_FILE")"
run "$ITEM_ID" --source-link "$LINK" --note "seen again"
assert_eq "same link again → exit 0" "0" "$RC"
assert_eq "same link again is not recorded" "false" "$(jq -r '.recorded' <<<"$OUT")"
assert_eq "same link again writes nothing" "$BEFORE" "$(cat "$ITEM_FILE")"

run "$ITEM_ID" --source-link "https://github.com/o/r/actions/runs/2" --note "seen on run 2"
assert_eq "another link is recorded" "true" "$(jq -r '.recorded' <<<"$OUT")"
assert_eq "another link adds one marker" "2" "$(grep -cF 'work-item-recurrence' "$ITEM_FILE")"

# A note holding ` -->` must not end the marker early, or the link would not be found again.
ODD="https://example.com/a?b=-->"
run "$ITEM_ID" --source-link "$ODD" --note "closes --> early? no"
assert_eq "a link holding --> is recorded" "true" "$(jq -r '.recorded' <<<"$OUT")"
BEFORE="$(cat "$ITEM_FILE")"
run "$ITEM_ID" --source-link "$ODD" --note "again"
assert_eq "a link holding --> is found again" "false" "$(jq -r '.recorded' <<<"$OUT")"
assert_eq "a link holding --> is not written twice" "$BEFORE" "$(cat "$ITEM_FILE")"

# The markers stay out of the item's normalized fields.
GOT="$(WIT_STORAGE_DIR="$STORE" bash "$ADAPTER/get-item.sh" "$ITEM_ID")"
assert_eq "markers do not count as blockers" "0" "$(jq -r '.blocked_by_count' <<<"$GOT")"

run "local-markdown:local/markdown#999" --source-link "$LINK" --note seen
assert_eq "missing item → exit 5" "5" "$RC"

[[ $FAILED -eq 0 ]] || exit 1
