#!/usr/bin/env bash
# Tests for ratio.py, the paired-sample ratio.
#
# The two behaviors under test are refusals, not calculations: the paired ratio
# is SUPPRESSED under concurrency (the arms are no longer load-matched, so
# pairing by index compares samples that never shared conditions), and arms of
# unequal length are rejected outright rather than silently truncated.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"
harness_require_python
RATIO="$SCRIPT_DIR/ratio.py"
readonly RATIO

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

write_samples() {
  local path="$1"
  shift
  : >"$path"
  local value
  for value in "$@"; do
    printf '%s 0\n' "$value" >>"$path"
  done
}

RUN_OUT=""
RUN_RC=0
run_ratio() {
  RUN_OUT="$(env "$@" "$HARNESS_PYTHON" "$RATIO" 2>&1)"
  RUN_RC=$?
}

write_samples "$WORK/old" 40 40 40 40
write_samples "$WORK/new" 10 10 10 10
write_samples "$WORK/short" 10 10

# --- 1. serial run reports the paired ratio, given enough pairs ---
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=1 BENCH_MIN_PAIRS=4
assert_eq "a serial run exits 0" "0" "$RUN_RC"
assert_contains "the paired ratio is reported" "median_paired_ratio=4.00x" "$RUN_OUT"
assert_contains "p95 is refused below its floor" "ratio_of_p95=REFUSED(n=4<20)" "$RUN_OUT"
# A gate that can be quietly relaxed is not a gate.
# discriminating-skip-required: without this assertion a lowered floor is
# indistinguishable in the report from a ratio drawn from a full sample set.
assert_contains "a lowered floor records itself on the reported line" \
  "OVERRIDE: min_pairs=4 (default 20)" "$RUN_OUT"

# --- 1b. the headline ratio has a floor of its own ---
# Two IDENTICAL arms measured on this class of host spread 0.78x to 17.12x at
# five pairs. A median of a handful of ratios is a number the data does not
# support, and this line already refuses two weaker statistics.
# discriminating-skip-required: the minimum-pairs refusal is the only thing this
# case proves.
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=1
assert_eq "too few pairs still exits 0" "0" "$RUN_RC"
assert_contains "the headline ratio is refused by name" \
  "median_paired_ratio=REFUSED(pairs=4<20)" "$RUN_OUT"
assert_not_contains "no ratio is printed below the floor" "median_paired_ratio=4.00x" "$RUN_OUT"
assert_contains "the raw per-pair ratios replace it" "raw per-pair ratios:" "$RUN_OUT"
assert_contains "the refusal cites the measured spread" "0.78x to 17.12x" "$RUN_OUT"
# The SUBORDINATE ratios are gated by the same floor. Gating only the headline
# left two quotable numbers beside an honest one, which is the same defect
# wearing a smaller label.
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

# --- 1c. a zero denominator is refused, never clamped to 1ms ---
# `max(percentile(new, p), 1.0)` turned an arm the clock could not resolve into
# a 1ms denominator and manufactured a ratio out of the clamp. That is where a
# 12.08x between two identical arms actually came from.
# discriminating-skip-required: this case is the only cover for the clamp.
write_samples "$WORK/subms" 0 0 0 0
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/subms" BENCH_CONC=1 BENCH_MIN_PAIRS=1
assert_eq "an unresolvable denominator still exits 0" "2" "$RUN_RC"
assert_contains "the all-zero arm is refused before any ratio prints" \
  "clock resolution" "$RUN_OUT"

# A denominator whose p50 is 0 but which has SOME non-zero samples reaches the
# percentile gate rather than the earlier all-zero refusal.
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

# --- 1d. paired median and ratio-of-p50 disagreeing is flagged ---
# The docstring predicts a drift spike moves one and not the other. Predicting
# it is not enough: the reader cannot tell which number is the noise.
# discriminating-skip-required: the disagreement flag has no other cover.
# The two statistics only diverge when the PAIRING carries information the
# per-arm percentiles throw away. Here each arm has the identical distribution
# (so ratio_of_p50 is 1.00x) while every pair is lopsided in alternating
# directions (so the paired median is ~50x). That is the drift shape the
# docstring predicts, reproduced deterministically.
write_samples "$WORK/dis_old" 100 1 100 1
write_samples "$WORK/dis_new" 1 100 1 100
run_ratio BENCH_OLD="$WORK/dis_old" BENCH_NEW="$WORK/dis_new" BENCH_CONC=1 BENCH_MIN_PAIRS=1
assert_eq "a disagreeing run exits 0" "0" "$RUN_RC"
assert_contains "the disagreement is flagged" "DISAGREEMENT:" "$RUN_OUT"
assert_contains "the flag says which number to trust" "Trust the paired median" "$RUN_OUT"

run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=1 BENCH_MIN_PAIRS=4
assert_not_contains "agreeing ratios are not flagged" "DISAGREEMENT:" "$RUN_OUT"

# --- 2. concurrency SUPPRESSES the ratio ---
# discriminating-skip-required: this case is the whole proof that the
# concurrency suppression exists.
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=4
assert_eq "a concurrent run still exits 0" "0" "$RUN_RC"
assert_contains "the ratio is suppressed by name" "SUPPRESSED: concurrency=4" "$RUN_OUT"
assert_not_contains "no paired ratio is printed under concurrency" "median_paired_ratio" "$RUN_OUT"
assert_contains "the suppression states the reason" "never shared conditions" "$RUN_OUT"

# --- 3. an unset BENCH_CONC FAILS rather than defaulting to serial ---
# Defaulting would silently re-enable the paired ratio under concurrency for
# any caller who forgot to pass it.
RUN_OUT="$(env -u BENCH_CONC BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" \
  "$HARNESS_PYTHON" "$RATIO" 2>&1)"
RUN_RC=$?
assert_eq "an unset BENCH_CONC is refused" "2" "$RUN_RC"
assert_contains "the refusal explains the danger of defaulting" "re-enable the paired ratio" "$RUN_OUT"

# --- 4. unequal arms are refused, not truncated ---
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/short" BENCH_CONC=1
assert_eq "unequal arms are refused" "2" "$RUN_RC"
assert_contains "the refusal names the silent truncation" "silently drop" "$RUN_OUT"

# --- 5. an all-zero comparison arm is refused ---
write_samples "$WORK/zeros" 0 0 0 0
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/zeros" BENCH_CONC=1
assert_eq "an all-zero comparison arm is refused" "2" "$RUN_RC"
assert_contains "the refusal names the clock resolution" "clock resolution" "$RUN_OUT"

# --- 6. a spliced row is refused HERE, not only in summarize.py ---
# This file promises that a caller invoking it directly cannot lose the
# concurrency suppression. A row guard living only in its sibling would be a
# hole in exactly that promise, and a spliced row parses as a plausible number.
# discriminating-skip-required: nothing else here proves the row shape is
# enforced by this file rather than inherited from its caller.
printf '120\n130 0\n' >"$WORK/spliced"
run_ratio BENCH_OLD="$WORK/spliced" BENCH_NEW="$WORK/short" BENCH_CONC=1
assert_eq "a spliced row is refused" "2" "$RUN_RC"
assert_contains "the refusal names the concurrent-append cause" "concurrent appends" "$RUN_OUT"

# --- 7. a non-integer BENCH_MIN_PAIRS is refused, never silently defaulted ---
run_ratio BENCH_OLD="$WORK/old" BENCH_NEW="$WORK/new" BENCH_CONC=1 BENCH_MIN_PAIRS=lots
assert_eq "a non-integer BENCH_MIN_PAIRS is refused" "2" "$RUN_RC"

# --- 8. the disagreement check inspects EVERY printed ratio, not just p50 ---
# A tail spike in one arm moves ratio_of_p95 while the paired median and
# ratio_of_p50 both sit at 1.00x. The p95 value was previously discarded at the
# call site, so a quotable 5.95x could sit beside two 1.00x figures with nothing
# saying they disagree. A statistic excluded from the check is a statistic that
# can be quoted while the rest of the line silently contradicts it.
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

# The negative arm. Three agreeing ratios must NOT be flagged, or the check
# fires on every run and flags nothing.
run_ratio BENCH_OLD="$WORK/spike_new" BENCH_NEW="$WORK/spike_new" BENCH_CONC=1
assert_not_contains "agreeing ratios are not flagged" "DISAGREEMENT" "$RUN_OUT"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: ratio suppression and pairing"
exit 0
