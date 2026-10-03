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

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

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

run_summarize() {
  capture env BENCH_LABEL="$1" BENCH_CONC="$2" BENCH_TIMES="$3" \
    "$HARNESS_PYTHON" "$SUMMARIZE"
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
capture env BENCH_CONC=1 BENCH_TIMES="$WORK/twenty" "$HARNESS_PYTHON" "$SUMMARIZE"
assert_eq "a missing BENCH_LABEL is refused" "2" "$RUN_RC"
assert_contains "the refusal explains why there is no default" "no defaults" "$RUN_OUT"

# --- 7. both percentiles print the interpolated and the nearest-rank value ---
run_summarize "arm" 1 "$WORK/twenty"
assert_contains "p50 pairs interpolated with nearest-rank" "p50=10ms(nearest-rank=10ms)" "$RUN_OUT"
assert_contains "p95 pairs interpolated with nearest-rank" "p95=19ms(nearest-rank=19ms)" "$RUN_OUT"

# --- 8. one sample dominating p95 raises OUTLIER naming both p95 values ---
{
  for ((i = 0; i < 19; i++)); do printf '100 0\n'; done
  printf '5000 0\n'
} >"$WORK/outlier"
run_summarize "arm" 1 "$WORK/outlier"
assert_contains "the outlier flag fires" "OUTLIER:" "$RUN_OUT"
assert_contains "the flag names p95 with the max sample" "p95=345ms" "$RUN_OUT"
assert_contains "the flag names p95 without the max sample" "without max sample 100ms" "$RUN_OUT"
assert_contains "the flag is followed by the raw samples" "raw samples (ms): 100 100" "$RUN_OUT"

# --- 9. a uniform fixture does not raise OUTLIER ---
run_summarize "arm" 1 "$WORK/twenty"
assert_not_contains "uniform samples are not flagged" "OUTLIER" "$RUN_OUT"

# --- 10. a refused p95 prints neither nearest-rank nor OUTLIER ---
run_summarize "arm" 1 "$WORK/nineteen"
assert_not_contains "a refused p95 has no nearest-rank" "p95=REFUSED(n=19<20)(nearest-rank" "$RUN_OUT"
assert_not_contains "a refused p95 has no outlier line" "OUTLIER" "$RUN_OUT"

run_percentiles() {
  capture env BENCH_PERCENTILES="$1" BENCH_LABEL=arm BENCH_CONC=1 BENCH_TIMES="$2" \
    "$HARNESS_PYTHON" "$SUMMARIZE"
}

# --- 11. unset BENCH_PERCENTILES reports p50 and p95, unchanged ---
# The whole line, so a default that drifts in any cell or column fails here.
DEFAULT_LINE="arm$(printf '%26s' '')conc=1   n=20   p50=10ms(nearest-rank=10ms) p95=19ms(nearest-rank=19ms) min=1ms max=20ms rc={0: 20}"
run_summarize "arm" 1 "$WORK/twenty"
assert_eq "unset BENCH_PERCENTILES prints the p50,p95 line" "$DEFAULT_LINE" "$RUN_OUT"
run_percentiles "50,95" "$WORK/twenty"
assert_eq "an explicit 50,95 prints the same line" "$DEFAULT_LINE" "$RUN_OUT"

# --- 12. an entry outside (0, 100) or not a number is refused ---
for bad in 0 100 abc -5 nan "50,,95" ""; do
  run_percentiles "$bad" "$WORK/twenty"
  assert_eq "BENCH_PERCENTILES='$bad' is refused" "2" "$RUN_RC"
  assert_contains "the refusal for '$bad' names the variable" "BENCH_PERCENTILES" "$RUN_OUT"
done

# --- 13. the floor applies to every listed entry: p99 needs 1/(1-0.99) = 100 ---
run_percentiles "50,99" "$WORK/twenty"
assert_eq "a refused p99 still exits 0" "0" "$RUN_RC"
assert_contains "p99 is refused at n=20" "p99=REFUSED(n=20<100)" "$RUN_OUT"
assert_contains "p50 is still reported" "p50=10ms(nearest-rank=10ms)" "$RUN_OUT"
assert_not_contains "an unlisted p95 is not reported" "p95" "$RUN_OUT"

# p99.9 needs 1/(1-0.999) = 1000 samples exactly, not one more from float error.
samples "$WORK/n999" 999
run_percentiles "99.9" "$WORK/n999"
assert_contains "p99.9 is refused at n=999 with floor 1000" "p99.9=REFUSED(n=999<1000)" "$RUN_OUT"
samples "$WORK/n1000" 1000
run_percentiles "99.9" "$WORK/n1000"
assert_not_contains "p99.9 is reported at n=1000" "REFUSED" "$RUN_OUT"

# --- 14. OUTLIER follows the highest listed percentile ---
# 10 20 30 40: p50 is 25ms; without the max it is 20ms, a 20% move.
printf '10 0\n20 0\n30 0\n40 0\n' >"$WORK/four"
run_percentiles "50" "$WORK/four"
assert_contains "OUTLIER names p50 when p50 is the highest listed" \
  "OUTLIER: one sample moves p50 (p50=25ms, without max sample 20ms); report the raw samples, not p50" \
  "$RUN_OUT"
run_percentiles "50,99" "$WORK/outlier"
assert_not_contains "a refused highest entry runs no OUTLIER check" "OUTLIER" "$RUN_OUT"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: summarize percentile floor"
exit 0
