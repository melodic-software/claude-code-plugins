#!/usr/bin/env bash
# Check the detector-findings severity crosswalk is argued rather than asserted.
#
#   scripts/check-detector-findings-crosswalk.sh          discover: print every
#                                                          crosswalk row's rule
#                                                          id and disposition
#   scripts/check-detector-findings-crosswalk.sh --check  fail on a row whose
#                                                          test cell is empty, a
#                                                          rule id that is not
#                                                          fully qualified, a
#                                                          malformed row, or a
#                                                          restated findings
#                                                          table
#
# The contract it enforces (docs/conventions/detector-findings/README.md, "The
# severity crosswalk"): severity.md decides a tier by TEST, so a threshold-to-tier
# mapping with no argument in it is nominal closure. An empty test cell is the
# machine-checkable half of that bar -- whether the argument is SOUND stays
# judgment, and the admission test is what carries it.
#
# This lived as a checklist in the issue that introduced the crosswalk, which
# would have disappeared when that issue closed. A bar nothing runs is a bar that
# decays on the first row nobody argues.
#
# The table is located by its exact header rather than by a row-prefix pattern,
# so a stray table elsewhere in the document can neither satisfy the check nor
# be dragged into it.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

doc="${CROSSWALK_DOC:-docs/conventions/detector-findings/README.md}"
header='| Rule id | What fires it | The test the disposition is argued from | Tier or disposition | Auto-applicable |'

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

if [[ ! -f "$doc" ]]; then
  echo "MISSING: $doc does not exist; the crosswalk contract has no subject." >&2
  exit 1
fi

awk -v want_header="$header" -v mode="$mode" -v doc="$doc" '
BEGIN { in_table = 0; seen_header = 0; rows = 0; errors = 0 }

# The findings-file table belongs to plugins/review/reference/findings-file-shape.md.
# Restating it here is the
# pointer-not-copy failure this convention is most likely to commit, because the
# crosswalk sits beside it.
/^\| Rank \| Tier \| Confidence/ {
  printf "RESTATED: %s:%d reproduces the findings-file table header, which findings-file-shape.md owns.\n", doc, NR > "/dev/stderr"
  errors++
}

$0 == want_header {
  if (seen_header) {
    printf "DUPLICATE: %s:%d carries a second crosswalk header; the table must be unique.\n", doc, NR > "/dev/stderr"
    errors++
  }
  seen_header = 1
  in_table = 1
  expect_separator = 1
  next
}

in_table && expect_separator {
  expect_separator = 0
  if ($0 !~ /^\|[ :|-]+\|$/) {
    printf "MALFORMED: %s:%d should be the crosswalk separator row.\n", doc, NR > "/dev/stderr"
    errors++
  }
  next
}

in_table {
  if ($0 !~ /^\|/) { in_table = 0; next }

  rows++

  # An ESCAPED pipe is legal in a cell -- the findings-file shape requires
  # authors to write a literal pipe as \| and this table is prose about rules,
  # which is exactly the content that carries them (regex alternation, shell
  # pipelines, type unions). Splitting on the bare character cannot tell \| from
  # |, so a correctly escaped author would be told they failed to escape. Hide
  # the escaped ones behind a byte that cannot occur in the source, split, then
  # restore -- so the count below judges only the pipes that really are cell
  # separators.
  line = $0
  gsub(/\\[|]/, "\001", line)

  n = split(line, cell, "|")

  # A well-formed 5-column row splits into 7 fields: an empty lead, five cells,
  # an empty tail. Any other count means a cell carries an UNescaped pipe, which
  # silently shifts every cell after it -- including the test cell.
  if (n != 7) {
    printf "MALFORMED: %s:%d splits into %d fields, not 7 -- an unescaped pipe shifts the cells. Write a literal pipe as \\|.\n", doc, NR, n > "/dev/stderr"
    errors++
    next
  }

  for (i = 2; i <= 6; i++) {
    gsub(/\001/, "\\|", cell[i])
  }

  for (i = 2; i <= 6; i++) {
    trimmed[i] = cell[i]
    gsub(/^[ \t]+|[ \t]+$/, "", trimmed[i])
  }

  # The whole point: the tier is argued in the row, not asserted beside it.
  if (trimmed[4] == "") {
    printf "UNARGUED: %s:%d rule %s states a disposition with an EMPTY test cell.\n", doc, NR, trimmed[2] > "/dev/stderr"
    errors++
  }

  # An em dash alone passes a non-empty check while arguing nothing.
  if (trimmed[4] != "" && trimmed[4] !~ /[A-Za-z]/) {
    printf "UNARGUED: %s:%d rule %s has a test cell with no prose in it.\n", doc, NR, trimmed[2] > "/dev/stderr"
    errors++
  }

  # One id form everywhere. An unqualified id in a cross-producer registry is a
  # collision waiting for the second detector, and the emitted-id-to-row
  # resolution this table enables would resolve to the wrong row on it.
  if (trimmed[2] !~ /^[a-z0-9-]+\/[a-z0-9-]+\/rule-[a-z0-9-]+$/) {
    printf "UNQUALIFIED: %s:%d rule id \"%s\" is not <plugin>/<skill>/rule-<slug>.\n", doc, NR, trimmed[2] > "/dev/stderr"
    errors++
  }

  if (seen_id[trimmed[2]]++) {
    printf "DUPLICATE: %s:%d rule id \"%s\" already has a row.\n", doc, NR, trimmed[2] > "/dev/stderr"
    errors++
  }

  for (i = 3; i <= 6; i++) {
    if (trimmed[i] == "") {
      printf "INCOMPLETE: %s:%d rule %s leaves column %d empty.\n", doc, NR, trimmed[2], i - 1 > "/dev/stderr"
      errors++
    }
  }

  if (mode == "discover") {
    printf "%-52s %s\n", trimmed[2], trimmed[5]
  }
}

END {
  if (!seen_header) {
    printf "MISSING: %s has no crosswalk table header.\n", doc > "/dev/stderr"
    errors++
  } else if (rows == 0) {
    printf "EMPTY: %s carries a crosswalk header with no rule rows.\n", doc > "/dev/stderr"
    errors++
  }
  if (errors > 0) { exit 1 }
  if (mode == "--check") {
    printf "Crosswalk OK: %d rule row(s), every disposition argued from a stated test.\n", rows
  }
}
' "$doc"
