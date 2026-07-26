#!/usr/bin/env bash
# Black-box contract test for check-coverage-complete.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# The cases that matter are the ones where a wrong answer is invisible: a
# malformed ledger must never read as "complete", and an unmarked box in a
# column that is not Done must never read as "incomplete".
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-coverage-complete.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# run <expected-exit> <label> [args...]
run() {
  local expected="$1" label="$2"
  shift 2
  local out actual
  out="$(bash "$SUT" "$@" 2>&1)"
  actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label (exit $actual)"
  else
    fail "$label — expected exit $expected, got $actual: $out"
  fi
}

ledger() {
  local path="$WORK/$1"
  shift
  {
    printf '# Coverage ledger\n\n'
    printf '| # | Corpus item | Depth criterion | Done |\n'
    printf '|---|-------------|-----------------|------|\n'
    printf '%s\n' "$@"
  } >"$path"
  printf '%s' "$path"
}

# --- complete ---------------------------------------------------------------

all_marked="$(ledger all-marked.md \
  '| 1 | alpha | its API reference read end to end | [x] |' \
  '| 2 | beta  | its changelog fetched this turn   | [X] |')"
run 0 "all rows marked passes" "$all_marked"

# An unmarked box in a NON-Done column is not an unmarked row. A blind
# `grep -q '\[ \]'` would fail this ledger, which is why the gate is
# column-aware rather than pattern-matched.
other_col="$(ledger other-column.md \
  '| 1 | alpha [ ] | criterion mentioning [ ] literally | [x] |')"
run 0 "unmarked box outside the Done column passes" "$other_col"

# --- incomplete -------------------------------------------------------------

one_unmarked="$(ledger one-unmarked.md \
  '| 1 | alpha | its API reference read end to end | [x] |' \
  '| 2 | beta  | its changelog fetched this turn   | [ ] |')"
run 1 "one unmarked row fails" "$one_unmarked"

none_marked="$(ledger none-marked.md \
  '| 1 | alpha | criterion | [ ] |' \
  '| 2 | beta  | criterion | [ ] |')"
run 1 "no rows marked fails" "$none_marked"

# --- fail closed ------------------------------------------------------------
# Every case below is a ledger the gate cannot honestly grade. Each must exit 2
# — never 0. A hand-edited or half-written ledger reading as "complete" is the
# exact failure this gate exists to prevent.

run 2 "missing file fails closed" "$WORK/does-not-exist.md"
run 2 "no arguments fails closed"

no_table="$WORK/no-table.md"
printf '# Coverage ledger\n\nNothing tabular here.\n' >"$no_table"
run 2 "no table at all fails closed" "$no_table"

no_rows="$WORK/no-rows.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
} >"$no_rows"
run 2 "header with zero data rows fails closed" "$no_rows"

# A Done column alone does not make a table the ledger. An unrelated status table
# would otherwise be graded as coverage — criterion 11 satisfied by a table about
# something else, with no corpus item ever enumerated.
foreign_table="$WORK/foreign-table.md"
{
  printf '# Notes\n\n'
  printf '| Done | Note |\n'
  printf '|------|------|\n'
  printf '| [x] | status |\n'
} >"$foreign_table"
run 2 "unrelated table with a Done column is not the ledger" "$foreign_table"

# ...and a real ledger later in the same document is still found.
foreign_then_real="$WORK/foreign-then-real.md"
{
  printf '| Done | Note |\n'
  printf '|------|------|\n'
  printf '| [x] | status |\n\n'
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 | alpha | criterion | [x] |\n'
} >"$foreign_then_real"
run 0 "a real ledger after an unrelated table is still graded" "$foreign_then_real"

partial_header="$WORK/partial-header.md"
{
  printf '| # | Corpus item | Done |\n'
  printf '|---|-------------|------|\n'
  printf '| 1 | alpha | [x] |\n'
} >"$partial_header"
run 2 "header missing the depth-criterion column fails closed" "$partial_header"

no_done_col="$WORK/no-done-column.md"
{
  printf '| # | Corpus item | Depth criterion |\n'
  printf '|---|-------------|-----------------|\n'
  printf '| 1 | alpha | criterion |\n'
} >"$no_done_col"
run 2 "table without a Done column fails closed" "$no_done_col"

mangled="$WORK/mangled.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 | alpha | criterion | [x] |\n'
  printf '| 2 | beta | criterion |\n'
} >"$mangled"
run 2 "row with too few columns fails closed" "$mangled"

# A stray pipe inside a cell shifts every column after it, so the cell read as
# Done is some other cell — an extra column is as ungradeable as a missing one.
wide="$WORK/too-wide.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 | alpha | criterion with a stray | pipe | [x] |\n'
} >"$wide"
run 2 "row with too many columns fails closed" "$wide"

# A marked box on a row with no depth criterion certifies nothing — there is no
# statement of what covering that item meant. Criterion 11 reads exit 0 as proof
# of coverage, so this must never be one.
no_criterion="$WORK/no-criterion.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 | alpha |  | [x] |\n'
} >"$no_criterion"
run 2 "marked row with an empty depth criterion fails closed" "$no_criterion"

no_item="$WORK/no-item.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 |  | criterion | [x] |\n'
} >"$no_item"
run 2 "marked row with an empty corpus item fails closed" "$no_item"

# The same emptiness on an UNMARKED row is still ungradeable — a ledger cannot be
# completed later against a criterion nobody wrote.
unmarked_no_criterion="$WORK/unmarked-no-criterion.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 | alpha |  | [ ] |\n'
} >"$unmarked_no_criterion"
run 2 "unmarked row with an empty depth criterion fails closed" "$unmarked_no_criterion"

junk_cell="$WORK/junk-cell.md"
{
  printf '| # | Corpus item | Depth criterion | Done |\n'
  printf '|---|-------------|-----------------|------|\n'
  printf '| 1 | alpha | criterion | done? |\n'
} >"$junk_cell"
run 2 "Done cell that is neither marked nor unmarked fails closed" "$junk_cell"

empty="$WORK/empty.md"
: >"$empty"
run 2 "empty file fails closed" "$empty"

# --- usage ------------------------------------------------------------------

run 0 "--help exits 0" --help
run 2 "unknown flag fails closed" --nope "$all_marked"
run 2 "two ledgers is a usage error" "$all_marked" "$one_unmarked"

# --- output contract --------------------------------------------------------

out="$(bash "$SUT" "$all_marked" 2>&1)"
if [[ "$out" == *"rows=2"* && "$out" == *"unmarked=0"* && "$out" == *"status=complete"* ]]; then
  pass "complete ledger prints a greppable summary"
else
  fail "complete ledger summary — got: $out"
fi

out="$(bash "$SUT" "$one_unmarked" 2>&1)"
if [[ "$out" == *"rows=2"* && "$out" == *"unmarked=1"* && "$out" == *"status=incomplete"* ]]; then
  pass "incomplete ledger prints a greppable summary"
else
  fail "incomplete ledger summary — got: $out"
fi

# The failing case must name WHICH rows are unmarked; "some row somewhere" sends
# the reader back to eyeball the table the gate exists to replace.
out="$(bash "$SUT" "$none_marked" 2>&1)"
if [[ "$out" == *"alpha"* && "$out" == *"beta"* ]]; then
  pass "incomplete ledger names the unmarked items"
else
  fail "incomplete ledger should name unmarked items — got: $out"
fi

if [[ "$fails" -eq 0 ]]; then
  printf '\nAll checks passed.\n'
  exit 0
fi
printf '\n%d check(s) failed.\n' "$fails" >&2
exit 1
