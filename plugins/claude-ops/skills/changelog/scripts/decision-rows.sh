#!/usr/bin/env bash
# Validate decision rows and optionally write the working set.
#
# Input TSV columns: lens, owner, sentence, items, state
# lens is correct, replace, adopt, or note. A skip row is an error.
# correct, replace, and adopt require a sentence.
# replace state must be nominated (never replaced).
#
#   decision-rows.sh < rows.tsv
#   decision-rows.sh --write <dir> < rows.tsv
set -euo pipefail

WRITE=""
if [[ "${1:-}" == "--write" ]]; then
  WRITE="${2:?decision-rows.sh: --write needs a directory}"
  shift 2
fi
if [[ $# -gt 0 ]]; then
  echo "decision-rows.sh: unknown argument: $1" >&2
  exit 2
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
# Tab-separated fields stay empty under awk. Bash `read` collapses a tab run.
if ! awk -F '\t' -v out="$tmp" '
  BEGIN { count = 0 }
  $0 ~ /^#/ || $0 ~ /^[[:space:]]*$/ { next }
  {
    lens = $1
    owner = $2
    sentence = $3
    items = $4
    state = $5
    if (lens == "skip") {
      print "decision-rows.sh: skip leaves no row" > "/dev/stderr"
      exit 1
    }
    if (lens != "correct" && lens != "replace" && lens != "adopt" && lens != "note") {
      print "decision-rows.sh: unknown lens: " lens > "/dev/stderr"
      exit 1
    }
    if ((lens == "correct" || lens == "replace" || lens == "adopt") && sentence == "") {
      print "decision-rows.sh: " lens " requires a sentence" > "/dev/stderr"
      exit 1
    }
    if (lens == "replace" && state != "nominated") {
      print "decision-rows.sh: replace state must be nominated, got " (state == "" ? "empty" : state) > "/dev/stderr"
      exit 1
    }
    printf "%s\t%s\t%s\t%s\t%s\n", lens, owner, sentence, items, state >> out
    count++
  }
  END { if (count == 0 && NR == 0) exit 0 }
' ; then
  exit 1
fi
count="$(grep -c . "$tmp" || true)"

if [[ -n "$WRITE" ]]; then
  mkdir -p "$WRITE"
  cp "$tmp" "$WRITE/decisions.tsv"
  printf 'wrote %s (%s rows)\n' "$WRITE/decisions.tsv" "$count"
else
  cat "$tmp"
  printf 'rows: %s\n' "$count" >&2
fi
