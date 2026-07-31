#!/usr/bin/env bash
# Black-box contract test for packet-seal.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# The cases that matter are the silent ones: an in-place rewrite of a sealed
# file must report CHANGED rather than pass, a file added after the seal must
# report UNSEALED rather than be trusted, and an unsealed packet must fail
# closed instead of reading as intact.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/packet-seal.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

last_out=""
run() {
  local expected="$1" label="$2"
  shift 2
  local actual
  last_out="$(bash "$SUT" "$@" 2>&1)"
  actual=$?
  if [[ "$actual" -eq "$expected" ]]; then
    pass "$label (exit $actual)"
  else
    fail "$label — expected exit $expected, got $actual: $last_out"
  fi
}

has() {
  if [[ "$last_out" == *"$1"* ]]; then
    pass "$2"
  else
    fail "$2 — output was: $last_out"
  fi
}

fresh_packet() {
  local p="$WORK/packet"
  rm -rf "$p"
  mkdir -p "$p"
  # A verbatim upstream citation carrying a deliberate misspelling — the content
  # class the sibling formatters were observed to damage, and the one whose
  # rewrite silently falsifies the finding it was cited to prove.
  printf 'upstream dictionary entry: "hte" corrects to "the"\n' >"$p/audit-notes.md"
  printf 'invocation record\n' >"$p/evidence.md"
  printf '%s' "$p"
}

# --- record then verify a untouched packet ----------------------------------

packet="$(fresh_packet)"
run 0 "record seals the packet" record "$packet"
has "sealed=2" "both packet files are sealed"
if [[ -f "$packet/packet.sha256" ]]; then
  pass "the manifest lands in the packet"
else
  fail "no manifest was written"
fi

run 0 "verify passes on an untouched packet" verify "$packet"
has "packet integrity: intact" "an untouched packet reports intact"
has "MATCH audit-notes.md" "each sealed file is reported"

# The manifest must not seal itself — re-recording would otherwise chase its
# own digest and never converge.
if ! grep -q 'packet.sha256$' "$packet/packet.sha256"; then
  pass "the manifest excludes itself"
else
  fail "the manifest seals its own name"
fi

# --- an in-place rewrite is the whole point ---------------------------------

packet="$(fresh_packet)"
run 0 "record for the rewrite case" record "$packet"
# Exactly the observed damage: a formatter "corrects" a deliberate misspelling
# inside a verbatim quotation.
printf 'upstream dictionary entry: "the" corrects to "the"\n' >"$packet/audit-notes.md"
run 1 "verify fails after an in-place rewrite" verify "$packet"
has "CHANGED audit-notes.md" "the rewritten file is named"
has "NOT INTACT" "the verdict is unambiguous"

# --- a file added after the seal is never silently trusted -------------------

packet="$(fresh_packet)"
run 0 "record for the added-file case" record "$packet"
printf 'later\n' >"$packet/audit-notes-2.md"
run 1 "verify fails on an unsealed file" verify "$packet"
has "UNSEALED audit-notes-2.md" "the unsealed file is named"

# --- a deleted file --------------------------------------------------------

packet="$(fresh_packet)"
run 0 "record for the deletion case" record "$packet"
rm -f "$packet/evidence.md"
run 1 "verify fails on a missing sealed file" verify "$packet"
has "MISSING evidence.md" "the missing file is named"

# --- fail closed ------------------------------------------------------------

packet="$(fresh_packet)"
run 2 "verify on an unsealed packet fails closed" verify "$packet"
run 2 "verify on a missing directory is a usage error" verify "$WORK/no-such-packet"
run 2 "record on a missing directory is a usage error" record "$WORK/no-such-packet"
run 2 "an unknown action is refused" seal "$packet"
run 2 "record without a packet is a usage error" record
run 2 "an extra argument is refused" record "$packet" extra
run 0 "--help exits clean" --help

# --- an empty packet seals to zero and verifies ------------------------------

empty="$WORK/empty-packet"
rm -rf "$empty"
mkdir -p "$empty"
run 0 "record on an empty packet runs" record "$empty"
has "sealed=0" "an empty packet seals zero files"
run 0 "verify on an empty sealed packet is intact" verify "$empty"

echo
if [[ $fails -eq 0 ]]; then
  echo "all packet-seal.sh contract tests passed"
  exit 0
fi
echo "$fails packet-seal.sh contract test(s) failed" >&2
exit 1
