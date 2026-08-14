#!/usr/bin/env bash
# Contract smoke test for the bench harness: lib-bench.sh helpers, plus one
# tiny-parameter run of each lane — bench-idle.sh, bench-load.sh, and
# trace-probe.sh — against the repo's own statusline-tee.sh under an isolated
# HOME. Asserts behaviour and output shape, never timing: the benchmarks
# themselves are not CI material (wall-clock numbers on shared runners are
# noise), but the harness must keep RUNNING from a clean checkout, because an
# unrunnable harness is exactly the defect that let #2521's measurements go
# unreproducible (#2582).
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

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

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

# --- lib: pace_sleep_arg (regression: 0 spent must pad a FULL second; the old
# --- inline "0.%03d" printed 1000 ms as "0.1000" = 0.1 s) --------------------
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

# --- bench-idle: a failing render aborts the run, never becomes a sample -----
BAD="$WORK/bad-entry.sh"
printf '#!/usr/bin/env bash\nexit 7\n' >"$BAD"
OUT="$(HOME="$HOME1" STATUSLINE_ENTRY="$BAD" bash "$BENCH_DIR/bench-idle.sh" 2 2>&1)"
RC=$?
if [[ $RC -ne 0 && "$OUT" == *"render failed"* ]]; then
  ok "bench-idle: failing render aborts instead of reporting numbers"
else
  fail "bench-idle: failing render rc=$RC out=$OUT"
fi

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
OUT="$(HOME="$HOME2" STATUSLINE_ENTRY="$BAD" bash "$BENCH_DIR/bench-load.sh" 1 1 2>&1)"
RC=$?
if [[ $RC -ne 0 && "$OUT" == *"render failed"* ]]; then
  ok "bench-load: failing render aborts instead of reporting numbers"
else
  fail "bench-load: failing render rc=$RC out=$OUT"
fi

# --- trace-probe: prints the pre-passthrough trace of the repo tee -----------
OUT="$(bash "$BENCH_DIR/trace-probe.sh" 2>&1)"
RC=$?
if [[ $RC -eq 0 && "$OUT" == *"=== pre-passthrough trace ==="* && "$OUT" == *"TRACE PATH:"* ]]; then
  ok "trace-probe: emits the pre-passthrough trace against the repo tee"
else
  fail "trace-probe: rc=$RC out=${OUT:0:400}"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
