#!/usr/bin/env bash
# shellcheck disable=SC2154  # FAILED/CASE_NUM initialized by the sourced helper
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
S="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create-item.sh"
source "$(dirname "$S")/../../lib/verb-test-helpers.sh"

assert_help "$S"
assert_usage_error "$S" --nope
assert_usage_error "$S" --title x --parent "github:o/r#1"
assert_usage_error "$S" --title x --type

STORE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
TYPED="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title "typed item" --type bug)"
assert_eq "--type reaches the emitted record" "bug" "$(jq -r '.type' <<<"$TYPED")"
assert_contains "--type reaches the stored file" \
  "$(cat "$(jq -r '.url' <<<"$TYPED" | sed 's#^file://##')")" 'type: "bug"'
assert_eq "an item created without --type projects null" "null" \
  "$(WIT_STORAGE_DIR="$STORE" bash "$S" --title untyped | jq -r '.type')"

WIT_STORAGE_DIR="$STORE" bash "$S" --title orphan --parent "local-markdown:local/markdown#999" >/dev/null 2>&1
assert_eq "a missing --parent is not-found (5), not a dead edge" "5" "$?"
WIT_STORAGE_DIR="$STORE" bash "$S" --title orphan --blocked-by "local-markdown:local/markdown#999" >/dev/null 2>&1
assert_eq "a missing --blocked-by is not-found (5), not a dead edge" "5" "$?"
rm -rf "$STORE"

close_child() {
  awk -v c="$2" '$0 == "state: \"open\"" { print "state: \"closed\""; if (c != "") print "closed_at: " c; next } { print }' \
    "$1" >"$1.new" && mv "$1.new" "$1"
}
STORE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
PARENT="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title parent | jq -r '.id')"
CHILD="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title "  T " --parent "$PARENT" | jq -r '.id')"
CHILD_FILE="$STORE/${CHILD##*#}.md"
ERR="$(mktemp "$TMP_ROOT/f.XXXXXX")"

OUT="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title T --parent "$PARENT" 2>"$ERR")"
assert_eq "an open sibling titled T → exit 0" "0" "$?"
assert_eq "an open sibling titled T prints its id" "$CHILD" "$(jq -r '.id' <<<"$OUT")"
assert_eq "an open sibling titled T creates no item" "2" "$(find "$STORE" -name '*.md' | wc -l | tr -d ' ')"
assert_contains "an open sibling titled T is named on stderr" "$(<"$ERR")" "$CHILD"

close_child "$CHILD_FILE" "\"$(jq -rn 'now - 3600 | todate')\""
OUT="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title T --parent "$PARENT" 2>"$ERR")"
assert_eq "a sibling closed 1h ago → exit 0" "0" "$?"
assert_eq "a sibling closed 1h ago prints its id" "$CHILD" "$(jq -r '.id' <<<"$OUT")"
assert_eq "a sibling closed 1h ago creates no item" "2" "$(find "$STORE" -name '*.md' | wc -l | tr -d ' ')"

OUT="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title T 2>"$ERR")"
assert_eq "without --parent a same-titled item is still created" "false" \
  "$(jq -r --arg c "$CHILD" '.id == $c' <<<"$OUT")"
rm -rf "$STORE"

STORE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
PARENT="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title parent | jq -r '.id')"
CHILD="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title T --parent "$PARENT" | jq -r '.id')"
close_child "$STORE/${CHILD##*#}.md" "\"$(jq -rn 'now - 172800 | todate')\""
OUT="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title T --parent "$PARENT" 2>"$ERR")"
assert_eq "a sibling closed 2 days ago → exit 0" "0" "$?"
assert_eq "a sibling closed 2 days ago does not block a new create" "false" \
  "$(jq -r --arg c "$CHILD" '.id == $c' <<<"$OUT")"
assert_eq "a sibling closed 2 days ago: the new item is a child of the parent" "$PARENT" \
  "$(jq -r '.parent_id' <<<"$OUT")"
rm -rf "$STORE"

STORE="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
PARENT="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title parent | jq -r '.id')"
CHILD="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title T --parent "$PARENT" | jq -r '.id')"
close_child "$STORE/${CHILD##*#}.md" ""
OUT="$(WIT_STORAGE_DIR="$STORE" bash "$S" --title T --parent "$PARENT" 2>"$ERR")"
assert_eq "a closed sibling with no closed_at does not block a new create" "false" \
  "$(jq -r --arg c "$CHILD" '.id == $c' <<<"$OUT")"
rm -rf "$STORE" "$ERR"

[[ $FAILED -eq 0 ]] || exit 1
