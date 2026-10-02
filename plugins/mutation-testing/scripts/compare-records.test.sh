#!/usr/bin/env bash
# Black-box contract test for compare-records.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir. Every
# expected line below is written from the record format in
# skills/audit/context/mutant-record.md, not from running the script.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/compare-records.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SHA=0123456789abcdef0123456789abcdef01234567
OTHER=fedcba9876543210fedcba9876543210fedcba98
T=$'\t'

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# row <path> <start> <end> <operator> <original> <replacement> <state>
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"; }

# rec <name> <sha> [rows...]: write a record file and print its path.
rec() {
  local f="$WORK/$1"
  shift
  printf '%s\n' "$1" >"$f"
  shift
  local r
  for r in "$@"; do printf '%s\n' "$r" >>"$f"; done
  printf '%s' "$f"
}

out=""
code=0
cmp() {
  out="$(bash "$SUT" "$@" 2>&1)"
  code=$?
}

expect() { # expect <label> <exit> [<line that must appear>...]
  local label="$1" want="$2" line ok=1
  shift 2
  [[ "$code" -eq "$want" ]] || ok=0
  for line in "$@"; do grep -qxF -- "$line" <<<"$out" || ok=0; done
  if ((ok)); then pass "$label (exit $code)"; else fail "$label - want exit $want and [$*], got exit $code: $out"; fi
}

expect_absent() { # expect_absent <label> <pattern>
  if grep -q -- "$2" <<<"$out"; then fail "$1 - unexpected '$2' in: $out"; else pass "$1"; fi
}

M1="$(row app.py 7 7 comparison-inversion 'if amount > LIMIT:' 'if amount <= LIMIT:' killed)"
M2="$(row app.py 8 8 statement-removal 'amount = amount * 0.9' pass killed)"
M2S="$(row app.py 8 8 statement-removal 'amount = amount * 0.9' pass survived)"
M3="$(row app.py 9 9 statement-removal 'amount = amount * 1.2' pass survived)"
M3K="$(row app.py 9 9 statement-removal 'amount = amount * 1.2' pass killed)"

# Identical non-empty records pass.
a="$(rec a1 "$SHA" "$M1" "$M2" "$M3")"
b="$(rec b1 "$SHA" "$M1" "$M2" "$M3")"
cmp "$a" "$b"
expect "identical records pass" 0 "K0 2 K1 2"
expect_absent "identical records name no loss" newly-surviving

# One lost kill fails and names it.
b="$(rec b2 "$SHA" "$M1" "$M2S" "$M3")"
cmp "$a" "$b"
expect "one lost kill blocks" 1 "newly-surviving app.py:8 statement-removal" "K0 2 K1 1"

# A gain is not a loss.
b="$(rec b3 "$SHA" "$M1" "$M2" "$M3K")"
cmp "$a" "$b"
expect "a gain passes" 0 "K0 2 K1 3"

# A key only in the after record is ignored.
EXTRA="$(row lib.py 3 3 statement-removal 'x = 1' pass survived)"
b="$(rec b4 "$SHA" "$M1" "$M2" "$M3" "$EXTRA")"
cmp "$a" "$b"
expect "a key only in the after record is ignored" 0

# A key detected before and missing after is a loss.
b="$(rec b5 "$SHA" "$M1" "$M3")"
cmp "$a" "$b"
expect "a detected key missing after is a loss" 1 "newly-surviving app.py:8 statement-removal"

# Nothing detected before proves nothing.
e="$(rec e1 "$SHA" "$M2S" "$M3")"
cmp "$e" "$e"
expect "an empty K0 refuses" 2
e="$(rec e2 "$SHA")"
cmp "$e" "$e"
expect "a record with no rows refuses" 2

# Mismatched shas refuse.
b="$(rec b6 "$OTHER" "$M1" "$M2" "$M3")"
cmp "$a" "$b"
expect "a sha mismatch refuses" 2

# Malformed records refuse.
cmp "$a" "$(rec m1 "$SHA" "$(printf 'app.py\t8\t8\tstatement-removal\tx\tkilled\n')")"
expect "a six-field row refuses" 2
cmp "$a" "$(rec m2 "$SHA" "$(row app.py 8 8 statement-removal x pass dead)")"
expect "an unknown state refuses" 2
cmp "$a" "$(rec m3 "$SHA" "$(row app.py eight 8 statement-removal x pass killed)")"
expect "a non-integer line refuses" 2
cmp "$a" "$(rec m4 "$SHA" "$(row app.py 8 8 statement-removal 'a\qb' pass killed)")"
expect "an unknown escape refuses" 2
cmp "$a" "$(rec m5 "$SHA" "$M1" "$M1")"
expect "a duplicate key refuses" 2
cmp "$a" "$(rec m6 "not-a-sha" "$M1")"
expect "a first line that is not a sha refuses" 2
cmp "$a"
expect "one argument is a usage error" 2
cmp "$a" "$WORK/absent"
expect "a missing file refuses" 2
: >"$WORK/empty"
cmp "$WORK/empty" "$a"
expect "an empty before file refuses" 2

# Timeout counts as detected on both sides.
TO="$(row app.py 7 7 comparison-inversion 'if amount > LIMIT:' 'if amount <= LIMIT:' timeout)"
cmp "$(rec t1 "$SHA" "$TO")" "$(rec t2 "$SHA" "$M1")"
expect "timeout then killed is not a loss" 0
cmp "$(rec t3 "$SHA" "$M1")" "$(rec t4 "$SHA" "$TO")"
expect "killed then timeout is not a loss" 0

# Invalid and no-coverage after a kill are losses.
INV="$(row app.py 7 7 comparison-inversion 'if amount > LIMIT:' 'if amount <= LIMIT:' invalid)"
NOC="$(row app.py 7 7 comparison-inversion 'if amount > LIMIT:' 'if amount <= LIMIT:' no-coverage)"
cmp "$(rec i1 "$SHA" "$M1")" "$(rec i2 "$SHA" "$INV")"
expect "killed then invalid is a loss" 1 "newly-surviving app.py:7 comparison-inversion"
cmp "$(rec n1 "$SHA" "$M1")" "$(rec n2 "$SHA" "$NOC")"
expect "killed then no-coverage is a loss" 1 "newly-surviving app.py:7 comparison-inversion"

# A multi-line statement removal fits one row through its escapes, and the
# escapes are part of the key: an escaped newline and an escaped backslash
# followed by n are different replacements.
ML="$(row app.py 4 6 block-removal 'if x:\n\treturn "a\\z"\nelse:' pass killed)"
cmp "$(rec ml1 "$SHA" "$ML")" "$(rec ml2 "$SHA" "$ML")"
expect "a multi-line original round-trips" 0 "K0 1 K1 1"
NL="$(row app.py 4 4 statement-removal 'x' 'a\nb' killed)"
BS="$(row app.py 4 4 statement-removal 'x' 'a\\nb' killed)"
cmp "$(rec bs1 "$SHA" "$NL")" "$(rec bs2 "$SHA" "$BS")"
expect "an escaped newline is not an escaped backslash" 1 "newly-surviving app.py:4 statement-removal"

# A tab inside a field must be escaped; a raw one splits the row.
cmp "$a" "$(rec raw "$SHA" "app.py${T}8${T}8${T}statement-removal${T}a${T}b${T}pass${T}killed")"
expect "a raw tab in a field refuses" 2

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'all passed\n'
