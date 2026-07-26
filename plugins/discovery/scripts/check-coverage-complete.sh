#!/usr/bin/env bash
# Deterministic gate for a /discovery:research coverage ledger.
#
# The ledger enumerates a bounded corpus one row per item, each with the depth
# criterion that counts as covering THAT item, and a Done box. This gate decides
# whether every box is marked — deterministically, with NO model involvement, so
# the verdict survives a context that would rather be finished. The research
# outcome gate cites this exit status rather than a reading of the table.
#
# Exit 0 = every row's Done box is marked (status=complete)
# Exit 1 = at least one row is unmarked (status=incomplete)
# Exit 2 = the ledger cannot be graded — missing, empty, no table, no rows, no
#          Done column, a short row, or a Done cell that is neither marked nor
#          unmarked — plus usage errors. FAIL CLOSED: a ledger this gate cannot
#          read is never reported as complete.
#
# Usage:
#   bash check-coverage-complete.sh <ledger-path>
#   bash check-coverage-complete.sh --help
#
# Ledger shape (the Done column is located by header name, not by position, so
# adding a column ahead of it does not silently change what is graded):
#
#   | # | Corpus item | Depth criterion | Done |
#   |---|-------------|-----------------|------|
#   | 1 | <item>      | <criterion>     | [x]  |
#
# Output (stdout, greppable): `rows=<n> unmarked=<m> status=<complete|incomplete>`
# On status=incomplete each unmarked row is named on stderr.

set -uo pipefail

usage() {
  # Sentinel range (not fixed line numbers) so the printed usage never silently
  # truncates when the header grows or shrinks on a future edit.
  sed -n '/^# Deterministic gate/,/^# Output/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

ledger=""

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help | -h)
    usage
    exit 0
    ;;
  -*)
    echo "error: unknown argument: $1" >&2
    exit 2
    ;;
  *)
    if [[ -n "$ledger" ]]; then
      echo "error: expected exactly one ledger path, got a second: $1" >&2
      exit 2
    fi
    ledger="$1"
    shift
    ;;
  esac
done

if [[ -z "$ledger" ]]; then
  echo "error: a ledger path is required" >&2
  exit 2
fi
if [[ ! -f "$ledger" ]]; then
  echo "error: ledger not found: $ledger" >&2
  exit 2
fi
if [[ ! -s "$ledger" ]]; then
  echo "error: ledger is empty: $ledger" >&2
  exit 2
fi

# The whole grade happens in awk so the Done column is read positionally within
# each row rather than pattern-matched across the line: a `[ ]` written inside a
# corpus item or a depth criterion is prose, not an unmarked row.
#
# awk exit codes mirror this script's: 0 complete, 1 incomplete, 2 ungradeable.
awk -v OFS=' ' '
BEGIN {
  # The mandated ledger header, lowercased. Every one must appear exactly once
  # before a table is accepted as the coverage ledger.
  required[1] = "#"; required[2] = "corpus item"
  required[3] = "depth criterion"; required[4] = "done"
}

function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

# Split a markdown table row into cells, dropping the empty fields the leading
# and trailing pipes produce. Returns the cell count.
#
# A backslash-escaped pipe is CONTENT, not a delimiter — a corpus item or depth
# criterion legitimately carries one (a TypeScript union `foo \| bar`, an alternation
# in a pattern). Splitting on it would inflate the cell count, and this gate treats a
# row whose width disagrees with the header as ungradeable, so a real ledger over a
# real corpus would be permanently unable to pass criterion 11 unless it was rewritten
# to say something less accurate. Protect them behind SUBSEP (\034, which markdown
# cannot produce) across the split, then restore.
function cells(line, out,   n, i, raw, c, cell_text) {
  gsub(/\\\|/, SUBSEP, line)
  n = split(line, raw, "|")
  c = 0
  for (i = 1; i <= n; i++) {
    if (i == 1 && trim(raw[i]) == "") continue
    if (i == n && trim(raw[i]) == "") continue
    cell_text = trim(raw[i])
    gsub(SUBSEP, "|", cell_text)
    out[++c] = cell_text
  }
  return c
}

function is_separator(line,   probe) {
  probe = line
  gsub(/[ \t|:-]/, "", probe)
  return probe == ""
}

/^[ \t]*\|/ {
  line = $0
  if (is_separator(line)) next

  ncell = cells(line, cell)
  if (ncell == 0) next

  if (!header_seen) {
    for (i = 1; i <= ncell; i++) {
      header_name[i] = cell[i]
      h = tolower(cell[i])
      seen_head[h]++
      if (h == "done") { done_col = i }
    }
    # The FULL mandated header is required — `#`, `Corpus item`, `Depth criterion`,
    # `Done` — each exactly once. A document may hold any number of tables, and a
    # near-miss would otherwise be graded as the coverage ledger, exiting 0 as proof
    # that a ledger this script never actually read was completed. Requiring each
    # column exactly once also rejects a duplicated header, where the column that a
    # given row value lands in is ambiguous.
    ok = 1
    for (r = 1; r <= 4; r++) if (seen_head[required[r]] != 1) ok = 0
    if (!ok) {
      done_col = 0
      delete seen_head
      next
    }
    header_cols = ncell
    header_seen = 1
    next
  }

  # A row whose width does not match the header cannot be graded — the Done
  # position is a guess at that point, and guessing is how a half-edited ledger
  # passes. Extra cells are as disqualifying as missing ones: a stray `|` inside
  # a corpus item shifts every column after it, so the cell read as Done is some
  # other cell entirely.
  if (ncell != header_cols) {
    printf "error: row %d has %d column(s), header has %d: %s\n", rows + 1, ncell, header_cols, line > "/dev/stderr"
    fatal = 1
    exit 2
  }

  rows++

  # Every non-Done cell must carry something. A marked box on a row whose corpus
  # item or depth criterion is blank certifies nothing — there is no statement of
  # what "covered" meant for that item — and criterion 11 reads this exit status
  # as proof of coverage, so accepting it would let a half-written ledger pass as
  # a complete one. That is the failure this gate exists to refuse.
  for (i = 1; i <= header_cols; i++) {
    if (i == done_col) continue
    if (cell[i] == "") {
      printf "error: row %d has an empty %s cell — a marked row must say what covering it meant: %s\n", rows, header_name[i], line > "/dev/stderr"
      fatal = 1
      exit 2
    }
  }

  box = cell[done_col]
  if (box ~ /^\[[xX]\][ \t]*$/) {
    next
  } else if (box ~ /^\[[ \t]*\][ \t]*$/) {
    unmarked++
    item = (header_cols >= 2 && done_col != 2) ? cell[2] : cell[1]
    printf "unmarked: row %d — %s\n", rows, item > "/dev/stderr"
  } else {
    printf "error: row %d has an ungradeable Done cell: %s\n", rows, (box == "" ? "<empty>" : box) > "/dev/stderr"
    fatal = 1
    exit 2
  }
}

END {
  # A rule that already decided the ledger is ungradeable jumps here, and an
  # unguarded verdict below would overwrite its exit code with a pass — which is
  # precisely the silent-success failure this gate is built to refuse.
  if (fatal) exit 2
  if (!header_seen) {
    print "error: no coverage table with a Done column found" > "/dev/stderr"
    exit 2
  }
  if (rows == 0) {
    print "error: coverage table has a header but no rows" > "/dev/stderr"
    exit 2
  }
  printf "rows=%d unmarked=%d status=%s\n", rows, unmarked, (unmarked ? "incomplete" : "complete")
  exit (unmarked ? 1 : 0)
}
' "$ledger"
status=$?

# awk exiting for a reason of its own (a broken interpreter, a signal) must not
# read as "complete". Anything outside the three documented codes is ungradeable.
case "$status" in
0 | 1 | 2) exit "$status" ;;
*)
  echo "error: grading failed unexpectedly (awk exit $status)" >&2
  exit 2
  ;;
esac
