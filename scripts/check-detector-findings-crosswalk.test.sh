#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SELF_DIR/.."

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

script="scripts/check-detector-findings-crosswalk.sh"
# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
tmp=""
fixture_tree::build tmp --label crosswalk

header='| Rule id | What fires it | The test the disposition is argued from | Tier or disposition | Auto-applicable |'
separator='|---|---|---|---|---|'
good_row='| a-plugin/a-skill/rule-thing | it fired | argued from the test because the limb matches | IMPORTANT | No |'

write_doc() {
  dest="$1"
  shift
  printf '%s\n' "# Doc" "" "$@" >"$dest"
}

expect() {
  label="$1"
  want="$2"
  doc="$3"
  want_msg="${4:-}"
  set +e
  CROSSWALK_DOC="$doc" bash "$script" --check >"$tmp/out" 2>"$tmp/err"
  got=$?
  set -e
  if [[ "$got" != "$want" ]]; then
    fail "$label — expected exit $want, got $got"
    cat "$tmp/err"
    return
  fi
  if [[ -n "$want_msg" ]] && ! grep -q -- "$want_msg" "$tmp/err"; then
    fail "$label — exit $got was right but the message was not; expected to see \"$want_msg\""
    cat "$tmp/err"
    return
  fi
  ok "$label"
}

write_doc "$tmp/conforming.md" "$header" "$separator" "$good_row"
expect "a conforming crosswalk passes" 0 "$tmp/conforming.md"

write_doc "$tmp/empty-test.md" "$header" "$separator" \
  '| a-plugin/a-skill/rule-thing | it fired |  | IMPORTANT | No |'
expect "an empty test cell fails" 1 "$tmp/empty-test.md" "EMPTY test cell"

write_doc "$tmp/dash-test.md" "$header" "$separator" \
  '| a-plugin/a-skill/rule-thing | it fired | — | IMPORTANT | No |'
expect "a test cell with no prose fails" 1 "$tmp/dash-test.md" "no prose in it"

write_doc "$tmp/unqualified.md" "$header" "$separator" \
  '| rule-thing | it fired | argued from the test | IMPORTANT | No |'
expect "an unqualified rule id fails" 1 "$tmp/unqualified.md" "UNQUALIFIED"

write_doc "$tmp/unescaped-pipe.md" "$header" "$separator" \
  '| a-plugin/a-skill/rule-thing | fired on a|b | argued from the test | IMPORTANT | No |'
expect "an unescaped pipe fails rather than shifting cells" 1 "$tmp/unescaped-pipe.md" "MALFORMED"

write_doc "$tmp/escaped-pipe.md" "$header" "$separator" \
  '| a-plugin/a-skill/rule-thing | fired on a\|b | argued from the test | IMPORTANT | No |'
expect "a correctly ESCAPED pipe passes" 0 "$tmp/escaped-pipe.md"

write_doc "$tmp/escaped-pipe-empty-test.md" "$header" "$separator" \
  '| a-plugin/a-skill/rule-thing | fired on a\|b |  | IMPORTANT | No |'
expect "an escaped pipe does not mask an empty test cell" 1 "$tmp/escaped-pipe-empty-test.md" "EMPTY test cell"

write_doc "$tmp/escaped-pipe-only-test.md" "$header" "$separator" \
  '| a-plugin/a-skill/rule-thing | it fired | \| | IMPORTANT | No |'
expect "a test cell of only an escaped pipe has no prose and fails" 1 "$tmp/escaped-pipe-only-test.md" "no prose in it"

write_doc "$tmp/duplicate-id.md" "$header" "$separator" "$good_row" "$good_row"
expect "a duplicate rule id fails" 1 "$tmp/duplicate-id.md" "already has a row"

write_doc "$tmp/incomplete.md" "$header" "$separator" \
  '| a-plugin/a-skill/rule-thing | it fired | argued from the test | IMPORTANT |  |'
expect "an empty auto-applicable cell fails" 1 "$tmp/incomplete.md" "leaves column 5 empty"

write_doc "$tmp/no-header.md" "some prose but no crosswalk"
expect "a missing crosswalk table fails" 1 "$tmp/no-header.md" "has no crosswalk table header"

write_doc "$tmp/no-rows.md" "$header" "$separator"
expect "a crosswalk header with no rules fails" 1 "$tmp/no-rows.md" "with no rule rows"

write_doc "$tmp/restated.md" "$header" "$separator" "$good_row" "" \
  '| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |'
expect "a restated findings-file table fails" 1 "$tmp/restated.md" "RESTATED"

write_doc "$tmp/stray-table.md" \
  '| Outcome | Determined by | Home |' \
  '|---|---|---|' \
  '| something | someone | somewhere |' \
  "" "$header" "$separator" "$good_row"
expect "an unrelated neighboring table is ignored" 0 "$tmp/stray-table.md"

expect "an absent document fails" 1 "$tmp/does-not-exist.md" "does not exist"

set +e
CROSSWALK_DOC="$tmp/conforming.md" bash "$script" --bogus >/dev/null 2>&1
got=$?
set -e
if [[ "$got" != 2 ]]; then
  fail "an unknown mode should exit 2, got $got"
else
  ok "an unknown mode exits 2"
fi

test_harness::report
