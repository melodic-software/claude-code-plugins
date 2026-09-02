#!/usr/bin/env bash
# Tests for summarize.py, the per-arm percentile reporter.
#
# The load-bearing behavior is the REFUSAL. A percentile p is expressible only
# from 1/(1-p) samples or more; below that, an interpolated value is the maximum
# sample wearing a percentile's name. Printing it anyway is how a harness
# manufactures a number, so these cases assert the refusal fires and that the
# raw samples are printed in its place.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
SUMMARIZE="$SCRIPT_DIR/summarize.py"
readonly SUMMARIZE

# Inline test helpers: self-contained, no external test lib (ships with the plugin).
FAILED=0
CASE_NUM=0
pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: [%d] %s\n' "$CASE_NUM" "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'FAIL: [%d] %s - expected %q got %q\n' "$CASE_NUM" "$1" "$2" "$3" >&2
  FAILED=$((FAILED + 1))
}
assert_eq() { if [[ "$3" == "$2" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then pass "$1"; else fail "$1" "*$2*" "$3"; fi
}
assert_not_contains() {
  if [[ "$3" != *"$2"* ]]; then pass "$1"; else fail "$1" "no *$2*" "$3"; fi
}

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT

samples() {
  local path="$1" count="$2" i
  : >"$path"
  for ((i = 1; i <= count; i++)); do
    printf '%s 0\n' "$i" >>"$path"
  done
}

RUN_OUT=""
RUN_RC=0
run_summarize() {
  RUN_OUT="$(BENCH_LABEL="$1" BENCH_CONC="$2" BENCH_TIMES="$3" \
    "$HARNESS_PYTHON" "$SUMMARIZE" 2>&1)"
  RUN_RC=$?
}

# --- 1. enough samples for both percentiles ---
samples "$WORK/twenty" 20
run_summarize "arm" 1 "$WORK/twenty"
assert_eq "twenty samples summarize cleanly" "0" "$RUN_RC"
assert_contains "n is reported" "n=20" "$RUN_OUT"
assert_contains "p50 is reported" "p50=" "$RUN_OUT"
assert_not_contains "p95 is NOT refused at the floor" "p95=REFUSED" "$RUN_OUT"

# --- 2. one sample below the p95 floor refuses p95 and only p95 ---
# discriminating-skip-required: the percentile floor is the only thing this
# case proves, and a skip here would leave the refusal unexercised.
samples "$WORK/nineteen" 19
run_summarize "arm" 1 "$WORK/nineteen"
assert_eq "nineteen samples still exit 0" "0" "$RUN_RC"
assert_contains "p95 is refused by name" "p95=REFUSED(n=19<20)" "$RUN_OUT"
assert_contains "p50 is still reported" "p50=" "$RUN_OUT"
assert_contains "the raw samples replace the refused percentile" "raw samples (ms):" "$RUN_OUT"
assert_contains "the refusal states the arithmetic" "1/(1-p) samples" "$RUN_OUT"

# --- 3. a single sample cannot express p50 either ---
samples "$WORK/one" 1
run_summarize "arm" 1 "$WORK/one"
assert_contains "one sample refuses p50" "p50=REFUSED(n=1<2)" "$RUN_OUT"

# --- 4. an empty sample file is refused, not reported as zeroes ---
: >"$WORK/empty"
run_summarize "arm" 1 "$WORK/empty"
assert_eq "an empty sample file is refused" "2" "$RUN_RC"
assert_contains "the refusal rejects printing zeroes" "would read as a result" "$RUN_OUT"

# --- 5. a spliced row from concurrent appends is refused, not parsed ---
printf '12 0\n34 0 99\n' >"$WORK/spliced"
run_summarize "arm" 4 "$WORK/spliced"
assert_eq "a malformed row is refused" "2" "$RUN_RC"
assert_contains "the refusal names the concurrent-append cause" "concurrent appends" "$RUN_OUT"

# --- 6. a missing environment variable is refused, never defaulted ---
RUN_OUT="$(BENCH_CONC=1 BENCH_TIMES="$WORK/twenty" "$HARNESS_PYTHON" "$SUMMARIZE" 2>&1)"
RUN_RC=$?
assert_eq "a missing BENCH_LABEL is refused" "2" "$RUN_RC"
assert_contains "the refusal explains why there is no default" "no defaults" "$RUN_OUT"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: summarize percentile floor"
exit 0
