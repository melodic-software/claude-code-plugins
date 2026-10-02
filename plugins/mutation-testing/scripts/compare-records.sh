#!/usr/bin/env bash
# compare-records.sh <before> <after>: the replay's compare step.
#
# Reads two mutant records (format: skills/audit/context/mutant-record.md),
# keys each mutant by path, line_start, line_end, operator and replacement, and
# prints `newly-surviving <path>:<line_start> <operator>` for every key detected
# before and not detected after, a key missing from the after record included.
# Detected means killed or timeout. Then one line `K0 <n> K1 <n>`: the mutants
# detected in each record.
#
# Exit 0: no loss. 1: at least one newly surviving mutant. 2: usage error, an
# unreadable or malformed record, mismatched shas, or an empty K0 (nothing
# detected before proves nothing).
set -uo pipefail

if (($# != 2)); then
  printf 'usage: compare-records.sh <before> <after>\n' >&2
  exit 2
fi
for f in "$1" "$2"; do
  [[ -f "$f" && -r "$f" ]] || {
    printf 'compare-records.sh: cannot read %s\n' "$f" >&2
    exit 2
  }
done

awk -F'\t' '
function bad(msg) { printf "compare-records.sh: %s:%d: %s\n", FILENAME, FNR, msg > "/dev/stderr"; err = 1; exit 2 }
function escaped_ok(s) { gsub(/\\[\\tn]/, "", s); return index(s, "\\") == 0 }
FNR == 1 {
  heads++
  if ($0 !~ /^[0-9a-f]+$/ || (length($0) != 40 && length($0) != 64)) bad("first line is not a commit sha")
  if (NR == 1) sha = $0
  else if ($0 != sha) bad("sha " $0 " does not match " sha)
  next
}
{
  if (NF != 7) bad("expected 7 tab-separated fields, found " NF)
  if ($1 == "" || $4 == "" || $5 == "") bad("empty path, operator or original")
  if ($2 !~ /^[1-9][0-9]*$/ || $3 !~ /^[1-9][0-9]*$/ || $3 + 0 < $2 + 0) bad("line_start and line_end must be integers, start <= end")
  if ($7 !~ /^(killed|survived|no-coverage|timeout|invalid)$/) bad("unknown state " $7)
  if (!escaped_ok($5) || !escaped_ok($6)) bad("a backslash not followed by t, n or a backslash")
  key = $1 SUBSEP $2 SUBSEP $3 SUBSEP $4 SUBSEP $6
  det = ($7 == "killed" || $7 == "timeout")
  if (NR == FNR) {
    if (key in before) bad("duplicate mutant")
    before[key] = det; order[++n] = key; label[key] = $1 ":" $2 " " $4
    k0 += det
  } else {
    if (key in after) bad("duplicate mutant")
    after[key] = det
    k1 += det
  }
}
END {
  if (err) exit 2
  if (heads != 2) { print "compare-records.sh: a record is empty" > "/dev/stderr"; exit 2 }
  if (k0 == 0) { print "compare-records.sh: K0 is empty; nothing detected before proves nothing" > "/dev/stderr"; exit 2 }
  lost = 0
  for (i = 1; i <= n; i++) {
    k = order[i]
    if (before[k] && !after[k]) { print "newly-surviving " label[k]; lost++ }
  }
  printf "K0 %d K1 %d\n", k0, k1
  exit lost ? 1 : 0
}' "$1" "$2"
