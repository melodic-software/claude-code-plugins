#!/usr/bin/env bash
# Regression tests for mechanics-sources.tsv: the pointer records the
# loading-mechanics record and the routing rubric cite as MS-<n>.
#
# Two checks, so an edit that breaks the records fails CI instead of passing
# unread: every row has the four columns with a well-formed id, docs URL, quote
# and as_of date, and the ids agree with the markdown that cites them. The
# Pointer records table in verified-mechanics.md lists exactly the TSV's ids,
# and no MS-<n> cited in either markdown file lacks a row. Fixture strings first
# prove the shape check rejects a bad row. No network: whether each quote is
# still on its page is a separate check.
# test-scope: plugins/instruction-placement/context/mechanics-sources.tsv
# test-scope: plugins/instruction-placement/context/verified-mechanics.md
# test-scope: plugins/instruction-placement/context/routing-rubric.md

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TSV="$SCRIPT_DIR/mechanics-sources.tsv"
MECHANICS="$SCRIPT_DIR/verified-mechanics.md"
RUBRIC="$SCRIPT_DIR/routing-rubric.md"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

# Prints one line per malformed row of the TSV on stdin; nothing when it is sound.
shape_errors() {
  awk -F'\t' '
    NR == 1 {
      if ($0 != "id\turl\tquote\tas_of") print "line 1: header is not id, url, quote, as_of"
      next
    }
    NF != 4 { print "line " NR ": " NF " columns, expected 4"; next }
    $1 !~ /^MS-[0-9]+$/ { print "line " NR ": id is not MS-<n>" }
    $2 !~ /^https:\/\/code\.claude\.com\/docs\/en\/[^ #]+#[^ ]+$/ { print "line " NR ": url is not a docs section URL" }
    $3 == "" { print "line " NR ": quote is empty" }
    $4 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ { print "line " NR ": as_of is not YYYY-MM-DD" }
    seen[$1]++ { print "line " NR ": id " $1 " repeats" }
    END { if (NR < 2) print "no records" }
  '
}
tsv_ids() { awk -F'\t' 'NR > 1 { print $1 }' "$1" | sort -u; }
table_ids() { grep -oE '^[|] MS-[0-9]+ [|]' "$1" | grep -oE 'MS-[0-9]+' | sort -u; }
cited_ids() { grep -ohE 'MS-[0-9]+' "$@" | sort -u; }

# --------------------------------------------------------------------------
# shape_errors on fixtures
# --------------------------------------------------------------------------
HEADER=$'id\turl\tquote\tas_of'
GOOD=$'MS-1\thttps://code.claude.com/docs/en/memory#how-it-works\tA sentence.\t2026-10-27'
assert_eq "a sound record passes" "" "$(printf '%s\n%s\n' "$HEADER" "$GOOD" | shape_errors)"
assert_eq "a wrong header is caught" "line 1: header is not id, url, quote, as_of" \
  "$(printf '%s\n%s\n' $'id\turl\tquote' "$GOOD" | shape_errors)"
assert_eq "a missing column is caught" "line 2: 3 columns, expected 4" \
  "$(printf '%s\n%s\n' "$HEADER" $'MS-1\thttps://code.claude.com/docs/en/memory#a\t2026-10-27' | shape_errors)"
assert_eq "a non-docs URL is caught" "line 2: url is not a docs section URL" \
  "$(printf '%s\n%s\n' "$HEADER" $'MS-1\thttps://example.com/memory#a\tA sentence.\t2026-10-27' | shape_errors)"
assert_eq "a URL with no section anchor is caught" "line 2: url is not a docs section URL" \
  "$(printf '%s\n%s\n' "$HEADER" $'MS-1\thttps://code.claude.com/docs/en/memory\tA sentence.\t2026-10-27' | shape_errors)"
assert_eq "a bad as_of is caught" "line 2: as_of is not YYYY-MM-DD" \
  "$(printf '%s\n%s\n' "$HEADER" $'MS-1\thttps://code.claude.com/docs/en/memory#a\tA sentence.\t27-10-2026' | shape_errors)"
assert_eq "a bad id is caught" "line 2: id is not MS-<n>" \
  "$(printf '%s\n%s\n' "$HEADER" $'MS-x\thttps://code.claude.com/docs/en/memory#a\tA sentence.\t2026-10-27' | shape_errors)"
assert_eq "a repeated id is caught" "line 3: id MS-1 repeats" \
  "$(printf '%s\n%s\n%s\n' "$HEADER" "$GOOD" "$GOOD" | shape_errors)"
assert_eq "a header alone is caught" "no records" "$(printf '%s\n' "$HEADER" | shape_errors)"

# --------------------------------------------------------------------------
# The shipped records
# --------------------------------------------------------------------------
assert_eq "every shipped row is well formed" "" "$(shape_errors <"$TSV")"
assert_eq "the Pointer records table lists exactly the TSV's ids" "" \
  "$(comm -3 <(table_ids "$MECHANICS") <(tsv_ids "$TSV") | tr -d '\t' | tr '\n' ' ')"
assert_eq "every MS-<n> the markdown cites has a row" "" \
  "$(comm -23 <(cited_ids "$MECHANICS" "$RUBRIC") <(tsv_ids "$TSV") | tr '\n' ' ')"

printf '\n%d case(s), %d failure(s)\n' "$CASE_NUM" "$FAILED"
[[ $FAILED -eq 0 ]] || exit 1
exit 0
