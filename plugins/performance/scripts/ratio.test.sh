#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
RATIO="$SCRIPT_DIR/ratio.py"
readonly RATIO

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

WORK="$(mktemp -d)"
readonly WORK
trap 'rm -rf "$WORK"' EXIT

write_samples() {
  local path="$1"
  shift
  : >"$path"
  local value
  for value in "$@"; do
    printf '%s 0\n' "$value" >>"$path"
  done
}

run_ratio() { capture env "$@" "$HARNESS_PYTHON" "$RATIO"; }

write_samples "$WORK/old" 40 40 40 40
write_samples "$WORK/new" 10 10 10 10
write_samples "$WORK/short" 10 10

run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=1 BENCH_MIN_PAIRS=4
assert_eq "a serial run exits 0" "0" "$RUN_RC"
assert_contains "the paired ratio is reported" "median_paired_ratio=4.00x" "$RUN_OUT"
assert_contains "p95 is refused below its floor" "ratio_of_p95=REFUSED(n=4<20)" "$RUN_OUT"
# discriminating-skip-required: without this assertion a lowered floor is
# indistinguishable in the report from a ratio drawn from a full sample set.
assert_contains "a lowered floor records itself on the reported line" \
  "OVERRIDE: min_pairs=4 (default 20)" "$RUN_OUT"

# discriminating-skip-required: the minimum-pairs refusal is the only thing this
# case proves.
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=1
assert_eq "too few pairs still exits 0" "0" "$RUN_RC"
assert_contains "the headline ratio is refused by name" \
  "median_paired_ratio=REFUSED(pairs=4<20)" "$RUN_OUT"
assert_not_contains "no ratio is printed below the floor" "median_paired_ratio=4.00x" "$RUN_OUT"
assert_contains "the raw per-pair ratios replace it" "raw per-pair ratios:" "$RUN_OUT"
assert_contains "the refusal cites the measured spread" "0.78x to 17.12x" "$RUN_OUT"
# discriminating-skip-required: without these two assertions an ungated
# ratio_of_p50 can still be quoted off a line whose headline is refused.
assert_contains "ratio_of_p50 is refused below the floor too" \
  "ratio_of_p50=REFUSED(pairs=4<20)" "$RUN_OUT"
assert_contains "ratio_of_p95 is refused below the floor too" \
  "ratio_of_p95=REFUSED(pairs=4<20)" "$RUN_OUT"
if [[ "$RUN_OUT" =~ ratio_of_p[0-9]+=[0-9] ]]; then
  fail "no numeric subordinate ratio prints below the floor" "all REFUSED" "$RUN_OUT"
else
  pass "no numeric subordinate ratio prints below the floor"
fi

# discriminating-skip-required: this case is the only cover for the clamp.
write_samples "$WORK/subms" 0 0 0 0
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/subms" BENCH_CONC=1 BENCH_MIN_PAIRS=1
assert_eq "a comparison arm the clock cannot resolve is refused" "2" "$RUN_RC"
assert_contains "the all-zero arm is refused before any ratio prints" \
  "clock resolution" "$RUN_OUT"

write_samples "$WORK/mostlyzero" 0 0 0 90
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/mostlyzero" BENCH_CONC=1 BENCH_MIN_PAIRS=1
assert_eq "a zero-p50 denominator exits 0" "0" "$RUN_RC"
assert_contains "a zero denominator percentile is refused, not clamped" \
  "ratio_of_p50=REFUSED(comparison p50=0ms, below clock resolution)" "$RUN_OUT"
if [[ "$RUN_OUT" =~ ratio_of_p50=[0-9] ]]; then
  fail "a clamped ratio is never printed" "REFUSED" "$RUN_OUT"
else
  pass "a clamped ratio is never printed"
fi

# discriminating-skip-required: the disagreement flag has no other cover.
write_samples "$WORK/dis_old" 100 1 100 1
write_samples "$WORK/dis_new" 1 100 1 100
run_ratio BENCH_OLD="$WORK/dis_old" BENCH_NEW="$WORK/dis_new" BENCH_CONC=1 BENCH_MIN_PAIRS=1
assert_eq "a disagreeing run exits 0" "0" "$RUN_RC"
assert_contains "the disagreement is flagged" "DISAGREEMENT:" "$RUN_OUT"
assert_contains "the flag says which number to trust" "Trust the paired median" "$RUN_OUT"

run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=1 BENCH_MIN_PAIRS=4
assert_not_contains "agreeing ratios are not flagged" "DISAGREEMENT:" "$RUN_OUT"

# discriminating-skip-required: this case is the whole proof that the
# concurrency suppression exists.
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=4
assert_eq "a concurrent run still exits 0" "0" "$RUN_RC"
assert_contains "the ratio is suppressed by name" "SUPPRESSED: concurrency=4" "$RUN_OUT"
assert_not_contains "no paired ratio is printed under concurrency" "median_paired_ratio" "$RUN_OUT"
assert_contains "the suppression states the reason" "never shared conditions" "$RUN_OUT"

capture env -u BENCH_CONC BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" \
  "$HARNESS_PYTHON" "$RATIO"
assert_eq "an unset BENCH_CONC is refused" "2" "$RUN_RC"
assert_contains "the refusal explains the danger of defaulting" "re-enable the paired ratio" "$RUN_OUT"

run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/short" BENCH_CONC=1
assert_eq "unequal arms are refused" "2" "$RUN_RC"
assert_contains "the refusal names the silent truncation" "silently drop" "$RUN_OUT"

write_samples "$WORK/zeros" 0 0 0 0
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/zeros" BENCH_CONC=1
assert_eq "an all-zero comparison arm is refused" "2" "$RUN_RC"
assert_contains "the refusal names the clock resolution" "clock resolution" "$RUN_OUT"

# discriminating-skip-required: nothing else here proves the row shape is
# enforced by this file rather than inherited from its caller.
printf '120\n130 0\n' >"$WORK/spliced"
run_ratio BENCH_OLD="$WORK/spliced" BENCH_NEW="$WORK/short" BENCH_CONC=1
assert_eq "a spliced row is refused" "2" "$RUN_RC"
assert_contains "the refusal names the concurrent-append cause" "concurrent appends" "$RUN_OUT"

run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=1 BENCH_MIN_PAIRS=lots
assert_eq "a non-integer BENCH_MIN_PAIRS is refused" "2" "$RUN_RC"

# discriminating-skip-required: this is the only case covering p95 in the
# disagreement check; without it the flag can regress to p50-only and every
# other assertion here still passes.
write_samples "$WORK/spike_old" 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 400
write_samples "$WORK/spike_new" 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10 10
run_ratio BENCH_OLD="$WORK/spike_old" BENCH_NEW="$WORK/spike_new" BENCH_CONC=1
assert_eq "a p95-only divergence still exits 0" "0" "$RUN_RC"
assert_contains "the paired median is unmoved by the tail spike" "median_paired_ratio=1.00x" "$RUN_OUT"
assert_contains "ratio-of-p50 is unmoved too" "ratio_of_p50=1.00x" "$RUN_OUT"
assert_contains "the divergence is flagged" "DISAGREEMENT" "$RUN_OUT"
assert_contains "the flag names the diverging statistic" "ratio-of-p95" "$RUN_OUT"

run_ratio BENCH_OLD="$WORK/spike_new" BENCH_NEW="$WORK/spike_new" BENCH_CONC=1
assert_not_contains "agreeing ratios are not flagged" "DISAGREEMENT" "$RUN_OUT"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: ratio suppression and pairing"
exit 0
