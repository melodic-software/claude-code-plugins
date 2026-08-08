#!/usr/bin/env bash
# Black-box contract test for check-explore-artifact.sh.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
#
# The cases that matter are the ones where a wrong answer is invisible. A slice
# holding no artifact, a stub index, or an index naming files nobody wrote must
# never read as "usable" — that reading is the whole failure this gate exists to
# refuse, because the caller's next move on a pass is to proceed to planning.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/check-explore-artifact.sh"

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

# stdout_has <expected-substring> <label> [args...] — the stdout line is what a
# parent greps, so its shape is part of the contract, not debug output.
stdout_has() {
  local needle="$1" label="$2"
  shift 2
  local out
  out="$(bash "$SUT" "$@" 2>/dev/null)"
  if [[ "$out" == *"$needle"* ]]; then
    pass "$label"
  else
    fail "$label — stdout lacked '$needle': $out"
  fi
}

# slice <name> — make an empty slice directory and echo its path.
slice() {
  local path="$WORK/$1"
  mkdir -p "$path"
  printf '%s' "$path"
}

# index <slice-dir> <body...> — write EXPLORE.md into a directory.
index() {
  local dir="$1"
  shift
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/EXPLORE.md"
}

sidecar() {
  local dir="$1" name="$2"
  shift 2
  mkdir -p "$dir"
  printf '%s\n' "$@" >"$dir/$name"
}

# --- usable -----------------------------------------------------------------

good="$(slice good)"
index "$good" '# EXPLORE — payments rounding' '| Section | File |' '| codebase | [EXPLORE-codebase.md](EXPLORE-codebase.md#codebase) |'
sidecar "$good" EXPLORE-codebase.md '---' 'section: codebase' '---'
run 0 "index plus its one named sidecar is usable" "$good"
stdout_has 'sidecars=1 missing=0 freshness=unchecked pointer=unchecked status=usable' "usable run reports its counts" "$good"

# A trailing slash is what a parent's own path variable usually carries.
run 0 "a trailing slash on the slice path is accepted" "$good/"

# The same sidecar named in both the abstract list and the section table is ONE
# sidecar. Counting references rather than distinct files would inflate the
# count and then disagree with the payload's own honest number.
dupes="$(slice dupes)"
index "$dupes" 'abstract for EXPLORE-tests.md' 'table row for EXPLORE-tests.md'
sidecar "$dupes" EXPLORE-tests.md 'content'
stdout_has 'sidecars=1 missing=0 freshness=unchecked pointer=unchecked status=usable' "a sidecar named twice counts once" "$dupes"

multi="$(slice multi)"
index "$multi" 'EXPLORE-codebase.md' 'EXPLORE-tests.md' 'EXPLORE-config.md'
sidecar "$multi" EXPLORE-codebase.md 'a'
sidecar "$multi" EXPLORE-tests.md 'b'
sidecar "$multi" EXPLORE-config.md 'c'
run 0 "three named sidecars all present is usable" "$multi"
run 0 "a matching --expect-sidecars passes" "$multi" --expect-sidecars 3

# The sanctioned collision path: the run wrote its whole set one level down.
sub="$(slice sub)"
index "$sub/rounding-scope" 'EXPLORE-codebase.md'
sidecar "$sub/rounding-scope" EXPLORE-codebase.md 'a'
run 0 "an index in a sub-slice one level below is found" "$sub"
stdout_has 'rounding-scope/EXPLORE.md' "the sub-slice path is the one reported" "$sub"

# --- unusable ---------------------------------------------------------------
# Every case below is a slice the parent must NOT proceed from.

run 1 "an empty slice with no index is unusable" "$(slice empty-slice)"

blank="$(slice blank-index)"
: >"$blank/EXPLORE.md"
run 1 "an empty index is unusable" "$blank"

# The observed production failure's on-disk shape: something got written, but it
# is a stub, not an index. A bare `test -s` passes this; this gate must not.
stub="$(slice stub)"
index "$stub" 'Reading src/payments/rounding.ts ...'
run 1 "an index naming no sidecar is unusable" "$stub"

# The angle-bracketed placeholder is not a filename.
placeholder="$(slice placeholder)"
index "$placeholder" 'sidecars are named EXPLORE-<section>.md'
run 1 "the literal EXPLORE-<section>.md placeholder does not count as a sidecar" "$placeholder"

# The truncation shape dispatch.md describes: an index naming files the run died
# before writing.
orphan="$(slice orphan)"
index "$orphan" 'EXPLORE-codebase.md' 'EXPLORE-tests.md'
sidecar "$orphan" EXPLORE-codebase.md 'a'
run 1 "an index naming a sidecar that was never written is unusable" "$orphan"
stdout_has 'sidecars=2 missing=1 freshness=unchecked pointer=unchecked status=unusable' "the missing count is reported" "$orphan"

hollow="$(slice hollow)"
index "$hollow" 'EXPLORE-codebase.md'
: >"$hollow/EXPLORE-codebase.md"
run 1 "an index naming an empty sidecar is unusable" "$hollow"

# The payload cross-check: the index and the payload disagree about how much was
# written, so one of them is wrong and the parent cannot tell which.
run 1 "a --expect-sidecars mismatch is unusable" "$multi" --expect-sidecars 5
run 1 "--expect-sidecars 0 against a real index is unusable" "$multi" --expect-sidecars 0

# --- fail closed ------------------------------------------------------------
# Everything below is a slice or an invocation the gate cannot honestly grade.
# Each must exit 2 — never 0.

run 2 "no slice path is a usage error" ""
run 2 "a nonexistent slice path is ungradeable" "$WORK/does-not-exist"

notdir="$WORK/a-file"
printf 'x\n' >"$notdir"
run 2 "a slice path that is a file is ungradeable" "$notdir"

# Two candidates: the gate cannot tell which run this dispatch produced, and
# accepting the wrong one would report a failed run as a success.
ambiguous="$(slice ambiguous)"
index "$ambiguous" 'EXPLORE-codebase.md'
sidecar "$ambiguous" EXPLORE-codebase.md 'a'
index "$ambiguous/other-scope" 'EXPLORE-codebase.md'
sidecar "$ambiguous/other-scope" EXPLORE-codebase.md 'b'
run 2 "a root index plus a sub-slice index is ambiguous" "$ambiguous"

two_sub="$(slice two-sub)"
index "$two_sub/scope-a" 'EXPLORE-codebase.md'
sidecar "$two_sub/scope-a" EXPLORE-codebase.md 'a'
index "$two_sub/scope-b" 'EXPLORE-codebase.md'
sidecar "$two_sub/scope-b" EXPLORE-codebase.md 'b'
run 2 "two sub-slice indexes are ambiguous" "$two_sub"

run 2 "an unknown flag is a usage error" "$good" --nope
run 2 "a second positional path is a usage error" "$good" "$multi"
run 2 "--expect-sidecars with no value is a usage error" "$good" --expect-sidecars
run 2 "--expect-sidecars with a non-integer is a usage error" "$good" --expect-sidecars two
run 2 "--expect-sidecars with a negative value is a usage error" "$good" --expect-sidecars -1

# An index deeper than one level is not a placement this workflow sanctions, so
# the slice reads as holding no artifact rather than silently reaching for it.
deep="$(slice deep)"
index "$deep/a/b" 'EXPLORE-codebase.md'
sidecar "$deep/a/b" EXPLORE-codebase.md 'a'
run 1 "an index two levels below the slice is not reached" "$deep"

# --- freshness (--newer-than) -----------------------------------------------
# Existence proves an artifact is there, not that THIS dispatch put it there.
# Every fixture below is a slice that passes every other check.

# Baselines are stamped with `touch -t` rather than written in sequence, so the
# ordering does not depend on the filesystem's mtime granularity.
old_baseline="$WORK/old-baseline"
: >"$old_baseline"
touch -t 200001010000 "$old_baseline"

future_baseline="$WORK/future-baseline"
: >"$future_baseline"
touch -t 203001010000 "$future_baseline"

run 0 "an index newer than the baseline is usable" "$good" --newer-than "$old_baseline"
stdout_has 'freshness=newer' "a checked-and-fresh index reports freshness=newer" "$good" --newer-than "$old_baseline"

# The finding this check exists for: a slice already holding a complete artifact
# set from an EARLIER run, graded after a dispatch that wrote nothing.
run 1 "an index no newer than the baseline is unusable" "$good" --newer-than "$future_baseline"
stdout_has 'freshness=stale' "a stale index reports freshness=stale" "$good" --newer-than "$future_baseline"

# An opt-in check that did not run must say so rather than reading as passed.
stdout_has 'freshness=unchecked pointer=unchecked' "omitted checks report unchecked" "$good"

# A baseline that is not there makes freshness ungradeable, and the caller asked
# for it — downgrading to `unchecked` would hand back a check that only appeared
# to run.
run 2 "--newer-than naming a missing baseline is ungradeable" "$good" --newer-than "$WORK/no-such-baseline"
run 2 "--newer-than with no value is a usage error" "$good" --newer-than

# --- pointer agreement (--expect-index) -------------------------------------

run 0 "a payload pointer naming the graded index is usable" "$good" --expect-index "$good/EXPLORE.md"
stdout_has 'pointer=matches' "an agreeing pointer reports pointer=matches" "$good" --expect-index "$good/EXPLORE.md"

# Two spellings of one file are one file. Comparing raw strings would report a
# mismatch here and halt a run whose artifact is fine.
run 0 "a differently-spelled path to the same index still matches" "$good" --expect-index "$good/./EXPLORE.md"

# The finding: the payload's pointer — and so its verification_request.target —
# names a file this gate never graded.
run 1 "a payload pointer naming another file is unusable" "$good" --expect-index "$multi/EXPLORE.md"
stdout_has 'pointer=mismatch' "a disagreeing pointer reports pointer=mismatch" "$good" --expect-index "$multi/EXPLORE.md"

run 1 "a payload pointer into a directory that does not exist is unusable" "$good" --expect-index "$WORK/nowhere/EXPLORE.md"
run 2 "--expect-index with no value is a usage error" "$good" --expect-index

# The opt-in checks compose, and a single verdict line carries all of them.
run 0 "all three opt-in checks together pass on a good slice" "$good" \
  --newer-than "$old_baseline" --expect-index "$good/EXPLORE.md" --expect-sidecars 1
stdout_has 'freshness=newer pointer=matches status=usable' "a fully-checked pass reports every field" "$good" \
  --newer-than "$old_baseline" --expect-index "$good/EXPLORE.md" --expect-sidecars 1

# --- help -------------------------------------------------------------------

run 0 "--help exits 0" --help
stdout_has 'Deterministic acceptance gate' "--help prints the header" --help

# ----------------------------------------------------------------------------

if [[ "$fails" -gt 0 ]]; then
  printf '\n%d test(s) failed\n' "$fails" >&2
  exit 1
fi
printf '\nall tests passed\n'
