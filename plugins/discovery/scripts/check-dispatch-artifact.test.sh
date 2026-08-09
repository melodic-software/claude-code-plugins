#!/usr/bin/env bash
# Black-box contract test for check-dispatch-artifact.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# The cases that matter are the ones where a wrong answer is invisible. A slice
# holding no artifact, a stub index, or an index naming files nobody wrote must
# never read as "usable" — that reading is the whole failure this gate exists to
# refuse, because the caller's next move on a pass is to proceed to planning.
#
# The shape suite runs TWICE, once per artifact family, because the gate serves
# both `/discovery:explore` and `/discovery:research` and the only difference
# between them is `--index-name`. Running it for EXPLORE.md alone would let a
# RESEARCH.md regression through on the strength of an explore-shaped pass,
# which is the same class of false evidence the gate itself refuses.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-dispatch-artifact.sh"

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

# run_raw <expected-exit> <label> [args...] — argv exactly as given, for the
# cases about the argument vector itself.
run_raw() {
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

# stdout_raw <expected-exit> <expected-substring> <label> [args...] — the stdout
# line is what a parent greps, so its shape is part of the contract, not debug
# output.
#
# The exit status is asserted here rather than left to a paired `run_raw` case,
# because a caller acts on BOTH halves: it branches on the status and then reads
# the line. An earlier revision checked only the substring, so a mutation that
# emitted the right line under the wrong status was invisible to every stdout
# case that had no exit-code twin over the same fixture — and at least one did
# not. `$?` is captured on the line immediately after the substitution; anything
# in between overwrites it.
#
# The two halves are reported INDEPENDENTLY rather than as a short-circuiting
# chain: when both drift at once, an `elif` would hide the exit-status failure
# behind the substring one and cost a second run to discover it.
stdout_raw() {
  local expected="$1" needle="$2" label="$3"
  shift 3
  local out actual ok=1
  out="$(bash "$SUT" "$@" 2>/dev/null)"
  actual=$?
  if [[ "$out" != *"$needle"* ]]; then
    fail "$label — stdout lacked '$needle': $out"
    ok=0
  fi
  if [[ "$actual" -ne "$expected" ]]; then
    fail "$label — exit was $actual, expected $expected"
    ok=0
  fi
  if [[ "$ok" -eq 1 ]]; then
    pass "$label"
  fi
}

# Set per suite; the wrappers below PREPEND --index-name so a case that ends in
# a value-less flag still fails for the reason it names rather than swallowing
# the injected flag as its value.
INDEX_NAME=""
PREFIX=""
WORK=""

run() {
  local expected="$1" label="$2"
  shift 2
  run_raw "$expected" "$label [$INDEX_NAME]" --index-name "$INDEX_NAME" "$@"
}

stdout_has() {
  local expected="$1" needle="$2" label="$3"
  shift 3
  stdout_raw "$expected" "$needle" "$label [$INDEX_NAME]" --index-name "$INDEX_NAME" "$@"
}

# slice <name> — make an empty slice directory and echo its path.
slice() {
  local path="$WORK/$1"
  mkdir -p "$path"
  printf '%s' "$path"
}

# index <slice-dir> <body...> — write the family's index into a directory.
index() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/$INDEX_NAME"
}

sidecar() {
  local dir="$1" name="$2"
  shift 2
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/$name"
}

# ============================================================================
# The shape suite — identical for both families, run once per family.
# ============================================================================
suite() {
  INDEX_NAME="$1"
  PREFIX="${INDEX_NAME%.md}"
  WORK="$WORKROOT/$PREFIX"
  mkdir -p "$WORK"

  # --- usable ---------------------------------------------------------------

  local good multi sub dupes blank stub placeholder orphan hollow
  local notdir ambiguous two_sub deep old_baseline future_baseline

  good="$(slice good)"
  index "$good" "# $PREFIX — payments rounding" '| Section | File |' \
    "| codebase | [$PREFIX-codebase.md]($PREFIX-codebase.md#codebase) |"
  sidecar "$good" "$PREFIX-codebase.md" '---' 'section: codebase' '---'
  run 0 "index plus its one named sidecar is usable" "$good"
  stdout_has 0 'sidecars=1 missing=0 freshness=unchecked pointer=unchecked status=usable' \
    "usable run reports its counts" "$good"

  # A trailing slash is what a parent's own path variable usually carries.
  run 0 "a trailing slash on the slice path is accepted" "$good/"

  # The same sidecar named in both the abstract list and the section table is
  # ONE sidecar. Counting references rather than distinct files would inflate
  # the count and then disagree with the payload's own honest number.
  dupes="$(slice dupes)"
  index "$dupes" "abstract for $PREFIX-tests.md" "table row for $PREFIX-tests.md"
  sidecar "$dupes" "$PREFIX-tests.md" 'content'
  stdout_has 0 'sidecars=1 missing=0 freshness=unchecked pointer=unchecked status=usable' \
    "a sidecar named twice counts once" "$dupes"

  multi="$(slice multi)"
  index "$multi" "$PREFIX-codebase.md" "$PREFIX-tests.md" "$PREFIX-config.md"
  sidecar "$multi" "$PREFIX-codebase.md" 'a'
  sidecar "$multi" "$PREFIX-tests.md" 'b'
  sidecar "$multi" "$PREFIX-config.md" 'c'
  run 0 "three named sidecars all present is usable" "$multi"
  run 0 "a matching --expect-sidecars passes" "$multi" --expect-sidecars 3

  # The sanctioned collision path: the run wrote its whole set one level down.
  # On the research side this is also the fan-out placement a parent assigns.
  sub="$(slice sub)"
  index "$sub/rounding-scope" "$PREFIX-codebase.md"
  sidecar "$sub/rounding-scope" "$PREFIX-codebase.md" 'a'
  run 0 "an index in a sub-slice one level below is found" "$sub"
  stdout_has 0 "rounding-scope/$INDEX_NAME" "the sub-slice path is the one reported" "$sub"

  # --- unusable -------------------------------------------------------------
  # Every case below is a slice the parent must NOT proceed from.

  run 1 "an empty slice with no index is unusable" "$(slice empty-slice)"

  blank="$(slice blank-index)"
  : >"$blank/$INDEX_NAME"
  run 1 "an empty index is unusable" "$blank"

  # The observed production failure's on-disk shape: something got written, but
  # it is a stub, not an index. A bare `test -s` passes this; this gate must not.
  stub="$(slice stub)"
  index "$stub" 'Reading src/payments/rounding.ts ...'
  run 1 "an index naming no sidecar is unusable" "$stub"
  # The no-sidecar branch reports through the same verdict line as every other
  # failure — a parent greps one shape, not one shape per failure path.
  stdout_has 1 'sidecars=0 missing=0 freshness=unchecked pointer=unchecked status=unusable' \
    "the no-sidecar branch reports the full verdict line" "$stub"

  # The angle-bracketed placeholder is not a filename.
  placeholder="$(slice placeholder)"
  index "$placeholder" "sidecars are named $PREFIX-<section>.md"
  run 1 "the literal <section> placeholder does not count as a sidecar" "$placeholder"

  # The truncation shape dispatch.md describes: an index naming files the run
  # died before writing.
  orphan="$(slice orphan)"
  index "$orphan" "$PREFIX-codebase.md" "$PREFIX-tests.md"
  sidecar "$orphan" "$PREFIX-codebase.md" 'a'
  run 1 "an index naming a sidecar that was never written is unusable" "$orphan"
  stdout_has 1 'sidecars=2 missing=1 freshness=unchecked pointer=unchecked status=unusable' \
    "the missing count is reported" "$orphan"

  hollow="$(slice hollow)"
  index "$hollow" "$PREFIX-codebase.md"
  : >"$hollow/$PREFIX-codebase.md"
  run 1 "an index naming an empty sidecar is unusable" "$hollow"

  # The payload cross-check: the index and the payload disagree about how much
  # was written, so one of them is wrong and the parent cannot tell which.
  run 1 "a --expect-sidecars mismatch is unusable" "$multi" --expect-sidecars 5
  run 1 "--expect-sidecars 0 against a real index is unusable" "$multi" --expect-sidecars 0

  # --- fail closed ----------------------------------------------------------
  # Everything below is a slice or an invocation the gate cannot honestly grade.
  # Each must exit 2 — never 0.

  run 2 "no slice path is a usage error" ""
  run 2 "a nonexistent slice path is ungradeable" "$WORK/does-not-exist"

  notdir="$WORK/a-file"
  printf 'x\n' >"$notdir"
  run 2 "a slice path that is a file is ungradeable" "$notdir"

  # Two candidates: the gate cannot tell which run this dispatch produced, and
  # accepting the wrong one would report a failed run as a success. For research
  # this is also what a synthesized fan-out looks like from the slice root.
  ambiguous="$(slice ambiguous)"
  index "$ambiguous" "$PREFIX-codebase.md"
  sidecar "$ambiguous" "$PREFIX-codebase.md" 'a'
  index "$ambiguous/other-scope" "$PREFIX-codebase.md"
  sidecar "$ambiguous/other-scope" "$PREFIX-codebase.md" 'b'
  run 2 "a root index plus a sub-slice index is ambiguous" "$ambiguous"

  two_sub="$(slice two-sub)"
  index "$two_sub/scope-a" "$PREFIX-codebase.md"
  sidecar "$two_sub/scope-a" "$PREFIX-codebase.md" 'a'
  index "$two_sub/scope-b" "$PREFIX-codebase.md"
  sidecar "$two_sub/scope-b" "$PREFIX-codebase.md" 'b'
  run 2 "two sub-slice indexes are ambiguous" "$two_sub"

  run 2 "an unknown flag is a usage error" "$good" --nope
  run 2 "a second positional path is a usage error" "$good" "$multi"
  run 2 "--expect-sidecars with no value is a usage error" "$good" --expect-sidecars
  run 2 "--expect-sidecars with a non-integer is a usage error" "$good" --expect-sidecars two
  run 2 "--expect-sidecars with a negative value is a usage error" "$good" --expect-sidecars -1

  # An index deeper than one level is not a placement this workflow sanctions,
  # so the slice reads as holding no artifact rather than silently reaching for
  # it.
  deep="$(slice deep)"
  index "$deep/a/b" "$PREFIX-codebase.md"
  sidecar "$deep/a/b" "$PREFIX-codebase.md" 'a'
  run 1 "an index two levels below the slice is not reached" "$deep"

  # --- freshness (--newer-than) ---------------------------------------------
  # Existence proves an artifact is there, not that THIS dispatch put it there.
  # Every fixture below is a slice that passes every other check.

  # Baselines are stamped with `touch -t` rather than written in sequence, so
  # the ordering does not depend on the filesystem's mtime granularity.
  old_baseline="$WORK/old-baseline"
  : >"$old_baseline"
  touch -t 200001010000 "$old_baseline"

  future_baseline="$WORK/future-baseline"
  : >"$future_baseline"
  touch -t 203001010000 "$future_baseline"

  run 0 "an index newer than the baseline is usable" "$good" --newer-than "$old_baseline"
  stdout_has 0 'freshness=newer' "a checked-and-fresh index reports freshness=newer" "$good" --newer-than "$old_baseline"

  # The finding this check exists for: a slice already holding a complete
  # artifact set from an EARLIER run, graded after a dispatch that wrote nothing.
  run 1 "an index no newer than the baseline is unusable" "$good" --newer-than "$future_baseline"
  stdout_has 1 'freshness=stale' "a stale index reports freshness=stale" "$good" --newer-than "$future_baseline"

  # An opt-in check that did not run must say so rather than reading as passed.
  stdout_has 0 'freshness=unchecked pointer=unchecked' "omitted checks report unchecked" "$good"

  # A baseline that is not there makes freshness ungradeable, and the caller
  # asked for it — downgrading to `unchecked` would hand back a check that only
  # appeared to run.
  run 2 "--newer-than naming a missing baseline is ungradeable" "$good" --newer-than "$WORK/no-such-baseline"
  run 2 "--newer-than with no value is a usage error" "$good" --newer-than

  # --- pointer agreement (--expect-index) -----------------------------------

  run 0 "a payload pointer naming the graded index is usable" "$good" --expect-index "$good/$INDEX_NAME"
  stdout_has 0 'pointer=matches' "an agreeing pointer reports pointer=matches" "$good" --expect-index "$good/$INDEX_NAME"

  # Two spellings of one file are one file. Comparing raw strings would report a
  # mismatch here and halt a run whose artifact is fine.
  run 0 "a differently-spelled path to the same index still matches" "$good" --expect-index "$good/./$INDEX_NAME"

  # The finding: the payload's pointer — and so its verification_request.target
  # — names a file this gate never graded.
  run 1 "a payload pointer naming another file is unusable" "$good" --expect-index "$multi/$INDEX_NAME"
  stdout_has 1 'pointer=mismatch' "a disagreeing pointer reports pointer=mismatch" "$good" --expect-index "$multi/$INDEX_NAME"

  run 1 "a payload pointer into a directory that does not exist is unusable" "$good" --expect-index "$WORKROOT/nowhere/$INDEX_NAME"
  run 2 "--expect-index with no value is a usage error" "$good" --expect-index

  # The opt-in checks compose, and a single verdict line carries all of them.
  run 0 "all three opt-in checks together pass on a good slice" "$good" \
    --newer-than "$old_baseline" --expect-index "$good/$INDEX_NAME" --expect-sidecars 1
  stdout_has 0 'freshness=newer pointer=matches status=usable' "a fully-checked pass reports every field" "$good" \
    --newer-than "$old_baseline" --expect-index "$good/$INDEX_NAME" --expect-sidecars 1
}

suite EXPLORE.md
suite RESEARCH.md

# ============================================================================
# --index-name itself — the one parameter the two families differ by.
# ============================================================================

INDEX_NAME="RESEARCH.md"
PREFIX="RESEARCH"
WORK="$WORKROOT/flag"
mkdir -p "$WORK"

flagged="$(slice flagged)"
index "$flagged" 'RESEARCH-tiers.md'
sidecar "$flagged" RESEARCH-tiers.md 'a'

# No default. A gate that guessed EXPLORE.md here would report a research run
# that succeeded as unusable — or, in a slice an earlier exploration also wrote
# to, report one that wrote nothing as usable.
run_raw 2 "a missing --index-name is a usage error" "$flagged"
run_raw 2 "--index-name with no value is a usage error" "$flagged" --index-name
run_raw 2 "--index-name without a .md suffix is rejected" "$flagged" --index-name RESEARCH
run_raw 2 "--index-name with a non-markdown suffix is rejected" "$flagged" --index-name RESEARCH.txt

# The stem is interpolated into an ERE for the sidecar scan, so a stem carrying
# regex metacharacters is refused rather than silently widening what counts as
# a sidecar.
run_raw 2 "--index-name with a dotted stem is rejected" "$flagged" --index-name RE.SEARCH.md
run_raw 2 "--index-name with a glob metacharacter is rejected" "$flagged" --index-name 'RE*.md'
run_raw 2 "--index-name with a path separator is rejected" "$flagged" --index-name 'sub/RESEARCH.md'

# Cross-family isolation, both directions: an index of the OTHER family is not
# this family's artifact, and must not be graded as one.
explore_only="$(slice explore-only)"
sidecar "$explore_only" EXPLORE.md 'EXPLORE-codebase.md'
sidecar "$explore_only" EXPLORE-codebase.md 'a'
run_raw 1 "a slice holding only EXPLORE.md is unusable under --index-name RESEARCH.md" \
  "$explore_only" --index-name RESEARCH.md
run_raw 0 "the same slice is usable under --index-name EXPLORE.md" \
  "$explore_only" --index-name EXPLORE.md

# The research coverage ledger is a sibling of the index, lowercase, and is NOT
# a sidecar. Counting it would inflate the count and disagree with the payload's
# honest number; grading its contents belongs to check-coverage-complete.sh.
#
# The fixture puts the ledger in BOTH places a wrong implementation could reach
# it from, because the gate harvests sidecar names out of the index TEXT and a
# ledger the index never mentions is unreachable by construction — an assertion
# no implementation of that design could fail is not coverage:
#
#   - NAMED IN THE INDEX. `artifact-shape.md` does not put the ledger in the
#     index's section table, but nothing stops a run mentioning it in the
#     restatement or the handoff, and real ones do. A harvest that dropped the
#     `RESEARCH-` anchor for a bare `[A-Za-z0-9._-]+\.md`, or that matched
#     case-insensitively (`research-checklist.md` matches `RESEARCH-…` under
#     `grep -oiE`), counts it and reports sidecars=2.
#   - ON DISK BESIDE THE INDEX. A rewrite that globbed the directory for
#     `RESEARCH-*.md` instead of reading the index picks it up on any
#     case-insensitive filesystem — which is what this repo is developed on.
#
# Either way the count inflates and the assertion below fails, which is the
# point of having it.
ledgered="$(slice ledgered)"
index "$ledgered" 'RESEARCH-tiers.md' \
  'Corpus coverage is tracked in research-checklist.md beside this index.'
sidecar "$ledgered" RESEARCH-tiers.md 'a'
sidecar "$ledgered" research-checklist.md '| # | Corpus item | Depth criterion | Done |'
stdout_raw 0 'sidecars=1 missing=0' "research-checklist.md is not counted as a sidecar" \
  "$ledgered" --index-name RESEARCH.md

# --- help -------------------------------------------------------------------
# --help answers before the required-argument check, so it works with no flags.

run_raw 0 "--help exits 0" --help
stdout_raw 0 'Deterministic acceptance gate' "--help prints the header" --help
stdout_raw 0 '--index-name' "--help documents the required index name" --help

# ----------------------------------------------------------------------------

if [[ "$fails" -gt 0 ]]; then
  printf '\n%d test(s) failed\n' "$fails" >&2
  exit 1
fi
printf '\nall tests passed\n'
