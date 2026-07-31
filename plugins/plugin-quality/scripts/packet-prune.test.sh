#!/usr/bin/env bash
# Black-box contract test for packet-prune.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# The cases that matter are the ones where a wrong answer destroys the
# deliverable: an old packet holding `item.md` must survive `--apply`, a bare
# invocation must delete nothing, and a root that is not an evidence tree must
# be refused before anything is walked.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/packet-prune.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

OLD="19990101T000000Z"
NEW="$(date -u +%Y%m%dT%H%M%SZ)"

# fresh_tree — rebuild a known evidence tree, echo its root.
fresh_tree() {
  local root="$WORK/data/evidence"
  rm -rf "$WORK/data"
  mkdir -p "$root/sess-1/plugin-a-skill/$OLD" \
    "$root/sess-1/plugin-a-skill/$NEW" \
    "$root/sess-1/plugin-b-hook/$OLD" \
    "$root/sess-2/plugin-c/not-a-nonce"
  : >"$root/sess-1/plugin-a-skill/$OLD/audit-notes.md"
  : >"$root/sess-1/plugin-a-skill/$NEW/audit-notes.md"
  : >"$root/sess-1/plugin-b-hook/$OLD/audit-notes.md"
  : >"$root/sess-1/plugin-b-hook/$OLD/item.md"
  : >"$root/sess-2/plugin-c/not-a-nonce/audit-notes.md"
  printf '%s' "$root"
}

# run <expected-exit> <label> [args...] — echoes captured output for reuse.
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

# verdict_is <nonce> <expected-verdict> <label> — assert the verdict reported for
# ONE named packet. `has` cannot do this: a run reporting several packets would
# let a verdict belonging to a different directory satisfy the match. Keyed on the
# nonce BASENAME rather than the full path, because the script prints the
# canonicalized path (`pwd -P`) and mktemp's `/tmp/...` is a different spelling of
# the same directory on Git Bash — comparing whole paths fails for a reason that
# has nothing to do with the behavior under test.
#
# Split on the FIRST space only, never on the last whitespace field: a path is not
# a whitespace-free token, and a TMPDIR containing a space would otherwise make
# every assertion compare against a path fragment and quietly stop testing.
verdict_is() {
  local nonce="$1" expected="$2" label="$3" line actual=""
  while IFS= read -r line; do
    [[ "${line#* }" == *"/$nonce" ]] || continue
    actual="${line%% *}"
    break
  done <<<"$last_out"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label — expected $expected for $nonce, got '${actual:-<no line>}'"
  fi
}

# --- dry run is the default -------------------------------------------------

root="$(fresh_tree)"
run 0 "bare invocation runs" --root "$root"
has "WOULD-DELETE" "old packet is reported as a would-delete"
has "(dry run" "dry run is announced"
if [[ -e "$root/sess-1/plugin-a-skill/$OLD/audit-notes.md" ]]; then
  pass "dry run deleted nothing"
else
  fail "dry run DELETED a packet — the default must never mutate"
fi

# --- the deliverable safeguard ----------------------------------------------

root="$(fresh_tree)"
run 0 "apply runs" --root "$root" --apply
has "RETAIN-ITEM" "a packet holding item.md is reported as retained"
if [[ -e "$root/sess-1/plugin-b-hook/$OLD/item.md" ]]; then
  pass "an OLD packet holding item.md survives --apply"
else
  fail "--apply DELETED an unemitted item.md — the one thing retention must never destroy"
fi
if [[ ! -e "$root/sess-1/plugin-a-skill/$OLD" ]]; then
  pass "an old packet without item.md is deleted under --apply"
else
  fail "--apply did not delete an expired packet"
fi
if [[ -e "$root/sess-1/plugin-a-skill/$NEW/audit-notes.md" ]]; then
  pass "a packet inside the window survives --apply"
else
  fail "--apply deleted a packet inside the retention window"
fi

# --- fail closed on an ungradable nonce -------------------------------------

if [[ -e "$root/sess-2/plugin-c/not-a-nonce/audit-notes.md" ]]; then
  pass "a directory whose name is not a nonce is never deleted"
else
  fail "--apply deleted a directory it could not grade the age of"
fi
has "UNPARSABLE" "an ungradable directory is reported, not silently kept"

# --- a nonce's SHAPE is not a date ------------------------------------------
#
# The character-shape regex is not a calendar check. `00000000T000000Z` has a
# nonce's exact shape, names no instant that exists, and sorts below every real
# cutoff — so a shape-only test grades it DELETE and `--apply` destroys a packet
# the fail-closed rule promises to keep. `20260231T000000Z` is the subtler one: a
# naive range check (month<=12, day<=31) passes Feb 31, which BSD `date` silently
# normalizes to Mar 3. Both must report UNPARSABLE and survive.

shaped="$WORK/shaped-not-real/evidence"
rm -rf "$WORK/shaped-not-real"
mkdir -p "$shaped/s/g/00000000T000000Z" "$shaped/s/g/20260231T000000Z" "$shaped/s/g/$OLD"
: >"$shaped/s/g/00000000T000000Z/audit-notes.md"
: >"$shaped/s/g/20260231T000000Z/audit-notes.md"
: >"$shaped/s/g/$OLD/audit-notes.md"
run 0 "apply runs over nonce-shaped non-dates" --root "$shaped" --apply
if [[ -e "$shaped/s/g/00000000T000000Z/audit-notes.md" ]]; then
  pass "an all-zero nonce survives --apply"
else
  fail "--apply DESTROYED 00000000T000000Z — a nonce-shaped non-date was graded as an ancient timestamp"
fi
if [[ -e "$shaped/s/g/20260231T000000Z/audit-notes.md" ]]; then
  pass "an impossible calendar day (Feb 31) survives --apply"
else
  fail "--apply DESTROYED 20260231T000000Z — a normalizing date parse graded a non-existent day"
fi
verdict_is "00000000T000000Z" UNPARSABLE "the all-zero nonce is reported UNPARSABLE, not DELETE"
verdict_is "20260231T000000Z" UNPARSABLE "the Feb-31 nonce is reported UNPARSABLE, not DELETE"
verdict_is "$OLD" DELETE "a real expired nonce is still reported DELETE"

# A dry run must reach the same verdicts — the calendar check belongs to grading,
# not to `--apply`, and an operator previewing the tree must see UNPARSABLE there
# rather than a WOULD-DELETE that never materializes.
shaped_dry="$WORK/shaped-dry/evidence"
rm -rf "$WORK/shaped-dry"
mkdir -p "$shaped_dry/s/g/00000000T000000Z"
: >"$shaped_dry/s/g/00000000T000000Z/audit-notes.md"
run 0 "dry run over a nonce-shaped non-date" --root "$shaped_dry"
verdict_is "00000000T000000Z" UNPARSABLE "a dry run grades the non-date UNPARSABLE, not WOULD-DELETE"

# Legitimate calendar values a too-strict round-trip would wrongly condemn. A leap
# day, the epoch, and a far-future value must all still grade as real nonces —
# `KEEP` or `DELETE` by age, never UNPARSABLE.
real="$WORK/real-nonces/evidence"
rm -rf "$WORK/real-nonces"
mkdir -p "$real/s/g/20240229T000000Z" "$real/s/g/19700101T000000Z" "$real/s/g/20991231T235959Z"
run 0 "dry run over legitimate calendar values" --root "$real"
verdict_is "20240229T000000Z" WOULD-DELETE "a leap day is graded as a real nonce"
verdict_is "19700101T000000Z" WOULD-DELETE "the epoch is graded as a real nonce"
verdict_is "20991231T235959Z" KEEP "a far-future nonce is graded as a real nonce"

# --- a broken date round-trip refuses LOUDLY, never silently ----------------
#
# Fail-closed is right, but silence is not: a `date` that exists yet cannot
# round-trip would grade EVERY packet UNPARSABLE, stopping retention forever
# while still printing a summary and exiting 0. The startup self-check runs the
# already-validated cutoff through the same path, so a broken userland is
# refused the way a missing `date` already is. Simulated with a stub `date`
# earlier on PATH that satisfies the dialect probe and the cutoff computation
# but fails every round-trip parse.

stubdir="$WORK/stub-bin"
rm -rf "$stubdir"
mkdir -p "$stubdir"
cat >"$stubdir/date" <<'STUB'
#!/usr/bin/env bash
# Round-trip parses use `-d <YYYY-MM-DD HH:MM:SS>`; the probe and cutoff use
# relative forms ("N days ago"). Fail only the former.
for a in "$@"; do
  [[ "$a" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\  ]] && exit 7
done
exec /usr/bin/env -i PATH=/usr/bin:/bin date "$@"
STUB
chmod +x "$stubdir/date"
stub_root="$WORK/stub-tree/evidence"
rm -rf "$WORK/stub-tree"
mkdir -p "$stub_root/s/g/$OLD"
: >"$stub_root/s/g/$OLD/audit-notes.md"
last_out="$(PATH="$stubdir:$PATH" bash "$SUT" --root "$stub_root" --apply 2>&1)"
stub_rc=$?
if [[ "$stub_rc" -eq 2 ]]; then
  pass "a date that cannot round-trip is refused with exit 2 (stub exit $stub_rc)"
else
  fail "a broken date round-trip exited $stub_rc, not 2 — retention would silently no-op: $last_out"
fi
if [[ "$last_out" == *"cannot round-trip a known-good nonce"* ]]; then
  pass "the refusal names the real cause"
else
  fail "the broken-round-trip refusal did not name its cause — output: $last_out"
fi
if [[ -e "$stub_root/s/g/$OLD/audit-notes.md" ]]; then
  pass "nothing was deleted when age could not be graded"
else
  fail "a packet was deleted despite an ungradable date implementation"
fi
# The regression guard: a round-trip strict enough to reject the two above must
# still grade a REAL old nonce as expired. Without this, a validator that
# refuses everything would pass both checks above and silently end retention.
if [[ ! -e "$shaped/s/g/$OLD" ]]; then
  pass "a genuinely old nonce is still deleted under --apply"
else
  fail "the calendar check broke retention — a real expired packet was not deleted"
fi

# --- containment holds per candidate, not just for the root -----------------
#
# Checking only the root is not containment: a symlink ANYWHERE on the way down
# yields a path whose real location is elsewhere, and rm -rf follows the real
# location. An independent review reproduced a delete outside the evidence root
# through a symlinked session directory.
#
# Needs real symlinks; on Git Bash that means MSYS=winsymlinks:nativestrict.
# Where they cannot be created, SKIP loudly rather than passing vacuously — a
# containment test that silently no-ops is worse than no test.

sym_root="$WORK/symlink-case"
rm -rf "$sym_root"
mkdir -p "$sym_root/data/evidence" "$sym_root/outside/slug/$OLD"
: >"$sym_root/outside/slug/$OLD/evidence.md"
if ln -s "$sym_root/outside" "$sym_root/data/evidence/sess-link" 2>/dev/null &&
  [[ -L "$sym_root/data/evidence/sess-link" ]]; then
  run 0 "apply runs over a symlinked session directory" --root "$sym_root/data/evidence" --apply
  has "ESCAPED" "a candidate resolving outside the root is reported as escaped"
  if [[ -e "$sym_root/outside/slug/$OLD/evidence.md" ]]; then
    pass "nothing outside the evidence root was deleted"
  else
    fail "--apply DELETED a directory outside the evidence root via a symlink"
  fi
else
  echo "SKIP - symlink containment case (cannot create symlinks here; set MSYS=winsymlinks:nativestrict on Git Bash)"
fi

# --- item.md protection is recursive ----------------------------------------

nested="$WORK/nested-item/evidence"
rm -rf "$WORK/nested-item"
mkdir -p "$nested/s/g/$OLD/raw"
: >"$nested/s/g/$OLD/raw/item.md"
run 0 "apply runs with a nested item.md" --root "$nested" --apply
has "RETAIN-ITEM" "a deliverable one directory down still retains the packet"
if [[ -e "$nested/s/g/$OLD/raw/item.md" ]]; then
  pass "an item.md in a subdirectory survives --apply"
else
  fail "--apply DELETED a nested item.md — the deliverable guard must not be depth-limited"
fi

# --- dry-run summary never claims deletions ---------------------------------

root="$(fresh_tree)"
run 0 "dry run for the summary check" --root "$root"
has "would-delete=" "a dry run reports would-delete="
if [[ "$last_out" != *"deleted="* ]]; then
  pass "a dry run never prints deleted="
else
  fail "a dry run printed deleted=, which a log reader cannot distinguish from a real delete"
fi

# --- an unusable --days is diagnosed as such, not as a missing binary -------

run 2 "an out-of-range --days is refused" --root "$(fresh_tree)" --days 999999999999
if [[ "$last_out" == *"did not yield a usable cutoff"* ]]; then
  pass "the overflow names the real cause"
else
  fail "the overflow was misdiagnosed — output: $last_out"
fi

# --- root containment -------------------------------------------------------

mkdir -p "$WORK/not-evidence/sess/slug/$OLD"
run 2 "a root not named 'evidence' is refused" --root "$WORK/not-evidence"
has "refusing to prune" "the refusal names its reason"
if [[ -e "$WORK/not-evidence/sess/slug/$OLD" ]]; then
  pass "the refused root was not walked"
else
  fail "a refused root was still pruned"
fi

run 2 "a missing root is a usage error" --root "$WORK/no-such-dir"
run 2 "--root is required" --days 5
run 2 "a non-numeric --days is refused" --root "$(fresh_tree)" --days thirty
run 2 "an unknown argument is refused" --root "$(fresh_tree)" --wipe
run 0 "--help exits clean" --help

# --- --days 0 expires everything except the protected packet ----------------

root="$(fresh_tree)"
run 0 "--days 0 runs" --root "$root" --days 0 --apply
if [[ -e "$root/sess-1/plugin-b-hook/$OLD/item.md" ]]; then
  pass "item.md survives even at --days 0"
else
  fail "--days 0 destroyed an unemitted item.md"
fi

echo
if [[ $fails -eq 0 ]]; then
  echo "all packet-prune.sh contract tests passed"
  exit 0
fi
echo "$fails packet-prune.sh contract test(s) failed" >&2
exit 1
