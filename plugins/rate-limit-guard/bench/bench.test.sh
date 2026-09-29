#!/usr/bin/env bash
# Contract smoke test for the bench harness: lib-bench.sh helpers, plus one
# tiny-parameter run of each lane — bench-idle.sh, bench-load.sh, and
# trace-probe.sh — against the repo's own statusline-tee.sh under an isolated
# HOME. Asserts behavior and output shape, never timing: the benchmarks
# themselves are not CI material (wall-clock numbers on shared runners are
# noise), but the harness must keep RUNNING from a clean checkout, because an
# unrunnable harness is exactly the defect that let #2521's measurements go
# unreproducible (#2582).
#
# The lane runs are GATED on BENCH_LANES: running a lane is running a benchmark
# however small its parameters, so an ordinary CI run stops after the lib
# assertions and reports the lanes as skipped coverage. BENCH_LANES=1 runs them
# — locally, or in CI through ci.yml's `bench_lanes` dispatch input, which is
# the deliberate run the #2582 guard rests on.
#
# Self-contained: defines its own assertion helpers — installed plugins are
# cache-isolated with no shared test lib.

set -uo pipefail

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$BENCH_DIR/lib-bench.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
# One summary shape for both exits: the gated stop after the lib assertions and
# the full run.
summary() {
  echo
  echo "PASS=$PASS FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Small spawn floors everywhere: the floor's VALUE is irrelevant here, only
# that the lanes run end to end.
export BENCH_FLOOR_N=2

# --- lib: median -------------------------------------------------------------
# shellcheck source=lib-bench.sh
source "$LIB"

# expect_eq LABEL ACTUAL EXPECTED
expect_eq() {
  if [[ "$2" == "$3" ]]; then
    ok "$1"
  else
    fail "$1: got '$2', want '$3'"
  fi
}

expect_eq "median: odd count picks the middle" "$(printf '5\n1\n3\n' | median)" "3"
expect_eq "median: even count picks the upper middle" "$(printf '1\n2\n3\n4\n' | median)" "3"
expect_eq "median: empty input yields 0" "$(printf '' | median)" "0"

# --- lib: pace_sleep_arg (regression: 0 spent must pad a FULL second; a bare
# --- "0.%03d" prints 1000 ms as "0.1000" = 0.1 s) ----------------------------
expect_eq "pace_sleep_arg: 0 ms spent pads a full second" "$(pace_sleep_arg 0)" "1.000"
expect_eq "pace_sleep_arg: 999 ms spent pads 1 ms" "$(pace_sleep_arg 999)" "0.001"
expect_eq "pace_sleep_arg: 600 ms spent pads 400 ms" "$(pace_sleep_arg 600)" "0.400"

# --- lib: now_ms assigns without printing, monotonically ---------------------
A=0
B=0
now_ms A
now_ms B
if [[ "$A" =~ ^[0-9]+$ && "$B" =~ ^[0-9]+$ ]] && ((B >= A)); then
  ok "now_ms: integer ms, monotone across two reads"
else
  fail "now_ms: A=$A B=$B"
fi

# --- lib: refuses bash without EPOCHREALTIME loudly --------------------------
OUT="$(bash -c 'unset EPOCHREALTIME; source "$1"' _ "$LIB" 2>&1)"
RC=$?
if [[ $RC -ne 0 && "$OUT" == *"requires bash >= 5.0"* ]]; then
  ok "lib: missing EPOCHREALTIME is a loud refusal, not an unbound-variable abort"
else
  fail "lib: EPOCHREALTIME guard rc=$RC out=$OUT"
fi

# --- the gate ----------------------------------------------------------------
# Everything above asserts pure functions and costs milliseconds. Everything
# below SPAWNS the lanes, which is a benchmark run whatever the parameters, and
# is the only part of this suite that spends real wall-clock seconds on a
# shared runner.
#
# The deferral prints a SKIP line rather than counting an ok. scripts/
# run-plugin-tests.sh reads `^SKIP:` and names the suite under "Suites with
# skipped coverage (exit 0 here is NOT evidence those cases ran)", which is
# what this is: eight cases that did not run. An ok would make the aggregate
# read as full coverage. --strict-skips therefore fails here, correctly — a
# caller declaring a fully provisioned environment is asking for every case to
# run, and BENCH_LANES=1 is how it gets them.
if [[ -z "${BENCH_LANES:-}" ]]; then
  echo "SKIP: bench lanes deferred; set BENCH_LANES=1 to run them"
  summary
  exit
fi

# --- bench-idle: smoke run against the repo tee, isolated HOME ---------------
HOME1="$WORK/home1"
mkdir -p "$HOME1"
OUT="$(HOME="$HOME1" bash "$BENCH_DIR/bench-idle.sh" 2 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$OUT" =~ ^idle\ n=2\ floor_before=[0-9]+\ floor_after=[0-9]+\ median=[0-9]+\ mean=[0-9]+\ samples=[0-9]+\ [0-9]+$ ]]; then
  ok "bench-idle: clean-checkout smoke run emits the report line"
else
  fail "bench-idle: smoke rc=$RC out=$OUT"
fi

# expect_render_abort LANE HOME SCRIPT [ARGS...] — a lane pointed at an entry
# that exits nonzero must abort and say so, never fold the failure into its
# numbers. Both lanes are checked the same way, against the same bad entry.
expect_render_abort() {
  local lane="$1" home="$2" out rc
  shift 2
  out="$(HOME="$home" STATUSLINE_ENTRY="$BAD" bash "$@" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 && "$out" == *"render failed"* ]]; then
    ok "$lane: failing render aborts instead of reporting numbers"
  else
    fail "$lane: failing render rc=$rc out=$out"
  fi
}

# --- bench-idle: a failing render aborts the run, never becomes a sample -----
BAD="$WORK/bad-entry.sh"
printf '#!/usr/bin/env bash\nexit 7\n' >"$BAD"
expect_render_abort bench-idle "$HOME1" "$BENCH_DIR/bench-idle.sh" 2

# --- bench-load: smoke run, 1 virtual session for 1 second -------------------
HOME2="$WORK/home2"
mkdir -p "$HOME2"
OUT="$(HOME="$HOME2" bash "$BENCH_DIR/bench-load.sh" 1 1 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$OUT" =~ ^load\ sessions=1\ secs=1\ floor_before=[0-9]+\ floor_after=[0-9]+\ renders=([0-9]+)\ median=[0-9]+\ mean=[0-9]+$ ]] &&
  ((BASH_REMATCH[1] >= 1)); then
  ok "bench-load: clean-checkout smoke run emits the report line with >=1 render"
else
  fail "bench-load: smoke rc=$RC out=$OUT"
fi

# --- bench-load: a failing render aborts the run -----------------------------
expect_render_abort bench-load "$HOME2" "$BENCH_DIR/bench-load.sh" 1 1

# --- trace-probe: prints the pre-passthrough trace of the repo tee -----------
OUT="$(bash "$BENCH_DIR/trace-probe.sh" 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$OUT" == *"=== pre-passthrough trace ==="* && "$OUT" == *"TRACE PATH:"* ]]; then
  ok "trace-probe: emits the pre-passthrough trace against the repo tee"
else
  fail "trace-probe: rc=$RC out=${OUT:0:400}"
fi

# --- trace-probe --count: the non-elected render spawns nothing --------------
# This is the #2521 property as a number, so a regression fails here instead of
# waiting for someone to read the trace.
OUT="$(bash "$BENCH_DIR/trace-probe.sh" --count 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$(grep -c ': processes spawned: [0-9]*$' <<<"$OUT")" -eq 6 &&
"$OUT" == *$'non-elected, unchanged input: processes spawned: 0\n'* &&
"$OUT" == *$'non-elected, changed input: processes spawned: 0\n'* ]]; then
  ok "trace-probe --count: six shapes reported, both non-elected renders spawn 0"
else
  fail "trace-probe --count: rc=$RC out=$OUT"
fi

# --- trace-probe --count: the counter sees a spawn --------------------------
# A stand-in tee that runs one external before the passthrough marker; a counter
# that reports 0 for it would make the case above vacuous.
FAKE="$WORK/fake-tee.sh"
# shellcheck disable=SC2016  # $HOME expands in the fake tee, not here
printf '#!/usr/bin/env bash\nmkdir -p "$HOME/.claude/rate-limit-guard/spool"\nset +o pipefail\n' >"$FAKE"
OUT="$(bash "$BENCH_DIR/trace-probe.sh" --count "$FAKE" 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$(grep -c ': processes spawned: 1$' <<<"$OUT")" -eq 6 ]]; then
  ok "trace-probe --count: one external before the marker counts as 1 in every shape"
else
  fail "trace-probe --count: fake tee rc=$RC out=$OUT"
fi

# --- trace-probe --count: pure-bash forks count too --------------------------
# A subshell and a command substitution spawn no external. bash 5.2 drops a PS4
# that is only in the environment, so the pid prefix must come from inside.
# shellcheck disable=SC2016  # $( ) runs in the fake tee, not here
printf '#!/usr/bin/env bash\n( : )\nx=$(printf x)\nset +o pipefail\n' >"$FAKE"
OUT="$(bash "$BENCH_DIR/trace-probe.sh" --count "$FAKE" 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$(grep -c ': processes spawned: 2$' <<<"$OUT")" -eq 6 ]]; then
  ok "trace-probe --count: a subshell and a command substitution count as 2 in every shape"
else
  fail "trace-probe --count: pure-bash fake tee rc=$RC out=$OUT"
fi

# --- trace-probe --count: an external with no stub is a loud failure ---------
printf '#!/usr/bin/env bash\nuname\nset +o pipefail\n' >"$FAKE"
OUT="$(bash "$BENCH_DIR/trace-probe.sh" --count "$FAKE" 2>&1)"
RC=$?
if [[ $RC -ne 0 && "$OUT" == *"no stub"* ]]; then
  ok "trace-probe --count: an unstubbed external aborts instead of going uncounted"
else
  fail "trace-probe --count: unstubbed rc=$RC out=$OUT"
fi

summary
