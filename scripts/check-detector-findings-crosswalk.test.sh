#!/usr/bin/env bash
# Self-test for check-detector-findings-crosswalk.sh.
#
# Every case is discriminating: it FAILS if the detector stops detecting. A
# gate whose test only ever feeds it a conforming document proves nothing,
# which is the failure mode this suite exists to rule out for a gate whose
# whole job is noticing an argument that was never made.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

script="scripts/check-detector-findings-crosswalk.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

failures=0
header='| Rule id | What fires it | The test the disposition is argued from | Tier or disposition | Auto-applicable |'
separator='|---|---|---|---|---|'
good_row='| a-plugin/a-skill/rule-thing | it fired | argued from the test because the limb matches | IMPORTANT | No |'

write_doc() {
  # $1 = destination, remaining args = body lines
  dest="$1"
  shift
  printf '%s\n' "# Doc" "" "$@" >"$dest"
}

expect() {
  # $1 = label, $2 = expected exit status, $3 = doc path,
  # $4 = OPTIONAL expected stderr substring.
  #
  # Asserting the message matters where a case could pass for the wrong reason:
  # a malformed fixture fails on exit status whatever the detector noticed, so a
  # status-only assertion would keep passing after the specific check it was
  # written for stopped working. Every case with a single intended cause names
  # it.
  label="$1"
  want="$2"
  doc="$3"
  want_msg="${4:-}"
  set +e
  CROSSWALK_DOC="$doc" bash "$script" --check >"$tmp/out" 2>"$tmp/err"
  got=$?
  set -e
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $label — expected exit $want, got $got"
    cat "$tmp/err"
    failures=$((failures + 1))
    return
  fi
  if [[ -n "$want_msg" ]] && ! grep -q -- "$want_msg" "$tmp/err"; then
    echo "FAIL: $label — exit $got was right but the message was not; expected to see \"$want_msg\""
    cat "$tmp/err"
    failures=$((failures + 1))
    return
  fi
  echo "ok: $label"
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

# The shape REQUIRES a literal pipe to be written \|, and this table is prose
# about rules -- regex alternation, shell pipelines, type unions. Rejecting a
# correctly escaped author would dead-end them in a required CI gate.
write_doc "$tmp/escaped-pipe.md" "$header" "$separator" \
  '| a-plugin/a-skill/rule-thing | fired on a\|b | argued from the test | IMPORTANT | No |'
expect "a correctly ESCAPED pipe passes" 0 "$tmp/escaped-pipe.md"

# An escaped pipe must not be able to smuggle a cell past the emptiness checks
# by restoring into one.
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

# A stray table elsewhere in the document must neither satisfy the check nor be
# dragged into it: the real table is located by its exact header.
write_doc "$tmp/stray-table.md" \
  '| Outcome | Determined by | Home |' \
  '|---|---|---|' \
  '| something | someone | somewhere |' \
  "" "$header" "$separator" "$good_row"
expect "an unrelated neighbouring table is ignored" 0 "$tmp/stray-table.md"

write_doc "$tmp/missing-file-probe.md" "$header" "$separator" "$good_row"
expect "an absent document fails" 1 "$tmp/does-not-exist.md" "does not exist"

set +e
CROSSWALK_DOC="$tmp/conforming.md" bash "$script" --bogus >/dev/null 2>&1
got=$?
set -e
if [[ "$got" != 2 ]]; then
  echo "FAIL: an unknown mode should exit 2, got $got"
  failures=$((failures + 1))
else
  echo "ok: an unknown mode exits 2"
fi

if ((failures > 0)); then
  echo "$failures test(s) failed."
  exit 1
fi
echo "All crosswalk-gate tests passed."
