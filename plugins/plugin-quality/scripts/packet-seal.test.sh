#!/usr/bin/env bash
# Black-box contract test for packet-seal.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# The cases that matter are the silent ones: an in-place rewrite of a sealed
# file must report CHANGED rather than pass, a file added after the seal must
# report UNSEALED rather than be trusted, an unsealed packet must fail closed
# instead of reading as intact, and "altered" must never share an exit code with
# "merely not sealed yet" — a packet routinely gains files after its last seal.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/packet-seal.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"
test_helpers::contract_lane

# lacks <phrase> <label> - the last run's combined output does NOT carry <phrase>.
lacks() {
  if [[ "$last_out" != *"$1"* ]]; then
    pass "$2"
  else
    fail "$2 — output was: $last_out"
  fi
}

fresh_packet() {
  local p="$WORK/packet"
  rm -rf "$p"
  mkdir -p "$p"
  # Stands in for a verbatim upstream citation — the content class the sibling
  # formatters were observed to damage, and the one whose rewrite silently
  # falsifies the finding it was cited to prove. The stand-in token is
  # deliberately NOT a real dictionary typo: this repo's own spell-check hook
  # would otherwise "correct" the fixture and defeat the test it anchors, which
  # is the very failure mode under test one level up.
  printf 'upstream dictionary entry: "zzqx" maps to "zzqy"\n' >"$p/audit-notes.md"
  printf 'invocation record\n' >"$p/evidence.md"
  printf '%s' "$p"
}

# --- record then verify an untouched packet ---------------------------------

packet="$(fresh_packet)"
run 0 "record seals the packet" record "$packet"
has "sealed=2" "both packet files are sealed"
if [[ -f "$packet/packet.sha256" ]]; then
  pass "the manifest lands in the packet"
else
  fail "no manifest was written"
fi

run 0 "verify passes on an untouched packet" verify "$packet"
has "sealed files intact" "an untouched packet reports its sealed files intact"
lacks "gen-" "no generation counters appear without a generation"
lacks "ACKNOWLEDGED" "no acknowledgment line appears without a generation"
has "BEFORE the first seal" "the intact verdict states what it cannot detect"
has "MATCH audit-notes.md" "each sealed file is reported"

# The manifest must not seal itself — re-recording would otherwise chase its
# own digest and never converge.
if ! grep -qF 'packet.sha256' "$packet/packet.sha256"; then
  pass "the manifest excludes itself"
else
  fail "the manifest seals its own name"
fi

# --- an in-place rewrite is the whole point ---------------------------------

packet="$(fresh_packet)"
run 0 "record for the rewrite case" record "$packet"
# Exactly the observed damage: a formatter "corrects" a deliberate misspelling
# inside a verbatim quotation.
printf 'upstream dictionary entry: "zzqy" maps to "zzqy"\n' >"$packet/audit-notes.md"
run 1 "verify fails after an in-place rewrite" verify "$packet"
has "CHANGED audit-notes.md" "the rewritten file is named"
has "NOT INTACT" "the verdict is unambiguous"

# --- a file added after the seal is never silently trusted -------------------

packet="$(fresh_packet)"
run 0 "record for the added-file case" record "$packet"
printf 'later\n' >"$packet/audit-notes-2.md"
run 3 "verify reports an unsealed file as incomplete, not altered" verify "$packet"
has "UNSEALED audit-notes-2.md" "the unsealed file is named"

# --- a filename is compared as a string, never as a pattern -----------------
#
# The unsealed check must not match a manifest name by regex. `audit-notes.md`
# read as a pattern also matches the sealed name `audit-notesXmd`, so an
# unsealed file would report as covered — a false negative in the one direction
# this check exists to prevent.

packet="$WORK/regex-packet"
rm -rf "$packet"
mkdir -p "$packet"
printf 'sealed\n' >"$packet/audit-notesXmd"
run 0 "record for the metacharacter case" record "$packet"
printf 'never sealed\n' >"$packet/audit-notes.md"
run 3 "verify reports an unsealed name that a regex would have matched" verify "$packet"
has "UNSEALED audit-notes.md" "the unsealed file is not swallowed by a pattern match"

# --- a deleted file --------------------------------------------------------

packet="$(fresh_packet)"
run 0 "record for the deletion case" record "$packet"
rm -f "$packet/evidence.md"
run 1 "verify fails on a missing sealed file" verify "$packet"
has "MISSING evidence.md" "the missing file is named"

# --- coverage is recursive --------------------------------------------------
#
# A packet holds raw artifacts as well as markdown. Content in a subdirectory
# that the manifest never mentioned is content a reader trusts on the strength
# of a manifest that says nothing about it.

packet="$(fresh_packet)"
mkdir -p "$packet/raw"
printf 'captured stdout\n' >"$packet/raw/invocation.txt"
run 0 "record seals a nested artifact" record "$packet"
has "sealed=3" "the nested file is counted"
if grep -qF 'raw/invocation.txt' "$packet/packet.sha256"; then
  pass "the manifest names the nested file by its relative path"
else
  fail "the nested file is missing from the manifest"
fi
run 0 "verify passes with a nested artifact untouched" verify "$packet"
printf 'tampered\n' >"$packet/raw/invocation.txt"
run 1 "verify detects a rewritten nested artifact" verify "$packet"
has "CHANGED raw/invocation.txt" "the nested rewrite is named"

# --- altered and merely-unsealed are DIFFERENT answers ----------------------
#
# A packet legitimately gains files after its last seal (contract.md at step 4,
# item.md at step 6). Collapsing "never sealed" into the altered-evidence exit
# would make the ordinary interrupted-run packet — the exact case resume exists
# for — report as tampered and get discarded.

packet="$(fresh_packet)"
run 0 "record for the unsealed-only case" record "$packet"
printf 'locked scope\n' >"$packet/contract.md"
run 3 "an unsealed-only packet exits 3, not 1" verify "$packet"
has "UNSEALED contract.md" "the unsealed file is named"
has "INCOMPLETE" "the verdict distinguishes incomplete from altered"
if [[ "$last_out" != *"NOT INTACT"* ]]; then
  pass "an unsealed-only packet is never called altered evidence"
else
  fail "an unsealed file was reported as altered evidence"
fi

# A CHANGED file still outranks an unsealed one.
printf 'rewritten\n' >"$packet/evidence.md"
run 1 "a changed file still exits 1 even alongside an unsealed one" verify "$packet"
has "CHANGED evidence.md" "the changed file is named"

# --- resealing must not launder a rewrite -----------------------------------

packet="$(fresh_packet)"
run 0 "record before the laundering attempt" record "$packet"
printf 'rewritten by a formatter\n' >"$packet/audit-notes.md"
run 1 "record refuses to reseal over an already-divergent file" record "$packet"
has "CHANGED audit-notes.md" "the divergent file is named at reseal time"
has "later notes are sealed into that generation" "the refusal says later notes go into a generation"
has "verify reads the latest one" "the refusal says which generation verify reads"
run 1 "verify still reports the divergence after the refused reseal" verify "$packet"
has "CHANGED audit-notes.md" "the rewrite was not laundered into a fresh digest"

# --- acknowledge writes a generation and keeps the original manifest ---------

packet="$(fresh_packet)"
run 0 "record before acknowledging" record "$packet"
original="$(cat "$packet/packet.sha256")"
cp "$packet/audit-notes.md" "$WORK/audit-notes.orig"
printf 'rewritten by a formatter\n' >"$packet/audit-notes.md"
printf 'a later note\n' >"$packet/audit-notes-2.md"
run 0 "acknowledge records a generation without replacing the original" record --acknowledge-divergence "$packet"
has "generation=2" "the first generation is packet.sha256.2"
has "original-preserved=" "the original manifest is named as preserved"
if [[ "$(cat "$packet/packet.sha256")" == "$original" ]]; then
  pass "packet.sha256 bytes are unchanged"
else
  fail "acknowledge overwrote packet.sha256"
fi
if grep -qF 'audit-notes-2.md' "$packet/packet.sha256.2"; then
  pass "the generation seals the later note"
else
  fail "the generation manifest does not name the later note"
fi
if ! grep -qF 'packet.sha256' "$packet/packet.sha256.2"; then
  pass "the generation does not seal manifest names"
else
  fail "the generation sealed a manifest name"
fi
run 1 "verify still reports the original divergence after acknowledge" verify "$packet"
has "CHANGED audit-notes.md" "acknowledge did not launder the original seal"
cp "$WORK/audit-notes.orig" "$packet/audit-notes.md"
run 1 "record refuses once a generation exists, even with the bytes restored" record "$packet"
has "acknowledged divergence" "the refusal names the acknowledged divergence"
if [[ "$(cat "$packet/packet.sha256")" == "$original" ]]; then
  pass "packet.sha256 survives a restore-then-record attempt"
else
  fail "a restore-then-record laundered packet.sha256"
fi
clean="$(fresh_packet)"
run 0 "record a clean packet" record "$clean"
run 2 "acknowledge refuses a packet that still matches" record --acknowledge-divergence "$clean"
has "no divergence to acknowledge" "a matching manifest is not an incident"

empty="$WORK/empty-packet"
mkdir -p "$empty"
run 2 "acknowledge without a manifest is a usage error" record --acknowledge-divergence "$empty"
has "needs an existing packet.sha256" "acknowledge requires the original seal"

# --- verify reads the latest generation --------------------------------------
#
# A generation must not read as `UNSEALED packet.sha256.N`, and a note sealed
# into it must not stay UNSEALED forever. It is graded on top of packet.sha256,
# never in place of it.

# make_acked_packet - sets $packet: audit-notes.md rewritten after the seal, a
# later note beside it, both acknowledged into generation 2.
make_acked_packet() {
  packet="$(fresh_packet)"
  run 0 "record before the divergence" record "$packet"
  cp "$packet/audit-notes.md" "$WORK/audit-notes.orig"
  printf 'rewritten by a formatter\n' >"$packet/audit-notes.md"
  printf 'a later note\n' >"$packet/audit-notes-2.md"
  run 0 "acknowledge writes generation 2" record --acknowledge-divergence "$packet"
}

make_acked_packet
run 1 "verify exits 1 on the original divergence, generation or not" verify "$packet"
has "CHANGED audit-notes.md" "the original divergence is still CHANGED"
has "ACKNOWLEDGED generation=2" "the acknowledgment stays visible"
has "GEN-MATCH audit-notes-2.md" "a note sealed into the generation matches it"
lacks "UNSEALED audit-notes-2.md" "a generation-sealed note is not unsealed"
lacks "UNSEALED packet.sha256.2" "a generation manifest is never reported unsealed"
lacks "outside the manifest" "no spurious outside-the-manifest line"
has "matched=1 changed=1 missing=0 unsealed=0 gen-matched=3 gen-changed=0 gen-missing=0" "the summary keeps its fields and appends the generation counters"

printf 'after the generation\n' >"$packet/audit-notes-3.md"
run 1 "verify exits 1 with a note added after the generation" verify "$packet"
has "UNSEALED audit-notes-3.md" "a note added after the generation is unsealed"
lacks "UNSEALED audit-notes-2.md" "the generation-sealed note stays sealed"

# A second edit of a file that already diverged, after the acknowledgment.
make_acked_packet
printf 'rewritten a second time\n' >"$packet/audit-notes.md"
run 1 "verify exits 1 on a second edit of an acknowledged file" verify "$packet"
has "GEN-CHANGED audit-notes.md" "the second edit is named against the generation"
has "gen-changed=1" "the generation tally counts it"

# Restore the altered file, then add notes: the generation must still take them.
make_acked_packet
original="$(cat "$packet/packet.sha256")"
cp "$WORK/audit-notes.orig" "$packet/audit-notes.md"
run 1 "a restore alone leaves the latest generation reporting a change" verify "$packet"
has "GEN-CHANGED audit-notes.md" "the restored file no longer matches generation 2"
printf 'a note after the restore\n' >"$packet/audit-notes-3.md"
run 0 "acknowledge after a restore writes the next generation" record --acknowledge-divergence "$packet"
has "generation=3" "the restore path writes generation 3"
if [[ -f "$packet/packet.sha256.3" ]]; then
  pass "packet.sha256.3 exists"
else
  fail "no generation 3 was written after the restore"
fi
run 0 "verify exits 0 once the restored packet is acknowledged" verify "$packet"
has "ACKNOWLEDGED generation=3" "exit 0 still prints the acknowledgment"
has "matched=2 changed=0 missing=0 unsealed=0 gen-matched=4 gen-changed=0 gen-missing=0" "every digest matches"
lacks "UNSEALED" "nothing is unsealed after the second acknowledgment"
run 1 "ordinary record is still refused after the restore path" record "$packet"
has "acknowledged divergence" "the laundering guard still names the acknowledged divergence"
if [[ "$(cat "$packet/packet.sha256")" == "$original" ]]; then
  pass "packet.sha256 is untouched by the restore path"
else
  fail "the restore path rewrote packet.sha256"
fi

printf 'a note after generation 3\n' >"$packet/audit-notes-4.md"
run 3 "a note added after the latest generation exits 3 when nothing else differs" verify "$packet"
has "UNSEALED audit-notes-4.md" "the new note is unsealed"
has "ACKNOWLEDGED generation=3" "the acknowledgment is printed on exit 3 too"
run 0 "acknowledge with nothing differing still seals the next generation" record --acknowledge-divergence "$packet"
has "generation=4" "the next generation follows the latest"
run 0 "verify exits 0 against generation 4" verify "$packet"
has "ACKNOWLEDGED generation=4" "the latest generation is the one reported"

printf 'edited after generation 4\n' >"$packet/audit-notes-2.md"
run 1 "editing a generation-only file exits 1 with the original clean" verify "$packet"
has "GEN-CHANGED audit-notes-2.md" "the edit is named against the generation"
has "matched=2 changed=0 missing=0 unsealed=0 gen-matched=4 gen-changed=1 gen-missing=0" "only the generation tally moved"
printf 'a later note\n' >"$packet/audit-notes-2.md"
rm -f "$packet/audit-notes-3.md"
run 1 "deleting a generation-only file exits 1" verify "$packet"
has "GEN-MISSING audit-notes-3.md" "the deletion is named against the generation"

# Generation numbers compare numerically: 10 is later than 9. A lexical sort
# would read 9 and grade the packet against a stale manifest.
make_acked_packet
mv "$packet/packet.sha256.2" "$packet/packet.sha256.10"
printf '%064d  audit-notes.md\n' 0 >"$packet/packet.sha256.9"
run 1 "verify reads generation 10, not 9" verify "$packet"
has "ACKNOWLEDGED generation=10" "the highest number is the latest generation"
has "GEN-MATCH audit-notes.md" "the file is graded against generation 10"
lacks "GEN-CHANGED" "generation 9 is not consulted"
run 0 "acknowledge numbers the next generation after the latest" record --acknowledge-divergence "$packet"
has "generation=11" "the next generation is 11"

# A name that only resembles a generation is a stray file, not a manifest: it is
# unsealed content until a generation seals it.
packet="$(fresh_packet)"
run 0 "record before the look-alike case" record "$packet"
printf 'stray\n' >"$packet/packet.sha256.2x"
run 3 "a look-alike name is unsealed content" verify "$packet"
has "UNSEALED packet.sha256.2x" "the look-alike is reported"
lacks "ACKNOWLEDGED" "the look-alike is not a generation"
printf 'rewritten by a formatter\n' >"$packet/audit-notes.md"
run 0 "acknowledge seals the look-alike as packet content" record --acknowledge-divergence "$packet"
run 1 "verify grades the look-alike against the generation" verify "$packet"
has "GEN-MATCH packet.sha256.2x" "the look-alike is sealed into the generation"
lacks "UNSEALED packet.sha256.2x" "a sealed look-alike is no longer unsealed"

# The next generation stops listing a file that is gone, so the acknowledging
# run is the last one to name it.
make_acked_packet
cp "$WORK/audit-notes.orig" "$packet/audit-notes.md"
rm -f "$packet/audit-notes-2.md"
run 0 "acknowledge after deleting a generation-sealed file" record --acknowledge-divergence "$packet"
has "GEN-MISSING audit-notes-2.md" "the deleted generation-sealed file is named"
has "acknowledged=2" "the deletion is counted with the restored file"
if ! grep -qF 'audit-notes-2.md' "$packet/packet.sha256.3"; then
  pass "generation 3 no longer lists the deleted file"
else
  fail "generation 3 still lists the deleted file"
fi

# --- symlinks are visible, and escaping ones are refused --------------------
#
# `-type f` cannot see a symlink, so an all-symlink packet enumerated as EMPTY
# and then verified "intact" — the worst answer an integrity tool can give.
# Needs real symlinks (MSYS=winsymlinks:nativestrict on Git Bash); SKIP loudly
# otherwise rather than passing vacuously.

sym="$WORK/symlink-packet"
rm -rf "$sym"
mkdir -p "$sym"
printf 'not the packet\n' >"$WORK/outside-target.md"
if ln -s "$WORK/outside-target.md" "$sym/audit-notes.md" 2>/dev/null && [[ -L "$sym/audit-notes.md" ]]; then
  run 2 "record refuses a symlink packet entry" record "$sym"
  has "packet entry is a symlink" "the refusal names the reason"
  if [[ ! -f "$sym/packet.sha256" ]]; then
    pass "no manifest is written for a packet it refused to seal"
  else
    fail "a manifest was written despite the refusal"
  fi
else
  echo "SKIP - symlink visibility case (cannot create symlinks here; set MSYS=winsymlinks:nativestrict on Git Bash)"
fi

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

contract_report packet-seal.sh
