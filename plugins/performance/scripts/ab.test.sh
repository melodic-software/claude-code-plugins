#!/usr/bin/env bash
# Tests for ab.sh, the interleaved A/B timer.
#
# The refusals are the point. A missing high-resolution clock must fail rather
# than fall back to date(1), because a process spawn per sample would measure
# the instrument alongside the subject; two arms that both exit 127 must be
# refused before timing, because a symmetric comparison of two commands that
# never ran is the classic false green; and concurrency must suppress the paired
# ratio, because the arms stop being load-matched the moment they overlap.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
AB="$SCRIPT_DIR/ab.sh"
readonly AB

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

run_ab() { capture bash "$AB" "$@"; }

# Measurable no-op: `printf` often records 0ms on CI, and ratio.py fail-closes
# when every comparison-arm sample is zero milliseconds.
NOOP="sleep 0.01"

# --- 1. a serial run reports both arms and the paired ratio ---
run_ab --a "$NOOP" --b "$NOOP" --iterations 4 --warmup 1 --min-pairs 4 \
  --label-a "A (baseline)" --label-b "B (candidate)"
assert_eq "a serial run exits 0" "0" "$RUN_RC"
assert_contains "the baseline arm is summarized" "A (baseline)" "$RUN_OUT"
assert_contains "the comparison arm is summarized" "B (candidate)" "$RUN_OUT"
assert_contains "every sample is accounted for" "n=4" "$RUN_OUT"
assert_contains "the paired ratio is reported for a serial run" "median_paired_ratio" "$RUN_OUT"

# --- 1b. the default refuses a headline ratio from too few pairs ---
# discriminating-skip-required: this is the only end-to-end proof that ab.sh
# carries the minimum-pairs floor through rather than reporting a ratio drawn
# from a handful of samples.
run_ab --a "$NOOP" --b "$NOOP" --iterations 4 --warmup 0
assert_eq "the default-floor run exits 0" "0" "$RUN_RC"
assert_contains "the headline ratio is refused below the floor" \
  "median_paired_ratio=REFUSED(pairs=4<20)" "$RUN_OUT"

# --- 2. concurrency suppresses the paired ratio ---
# discriminating-skip-required: this case is the only end-to-end proof that
# ab.sh propagates the concurrency suppression rather than reporting a ratio
# over arms that never shared conditions.
run_ab --a "$NOOP" --b "$NOOP" --iterations 4 --warmup 0 --concurrency 2
assert_eq "a concurrent run exits 0" "0" "$RUN_RC"
assert_contains "the ratio is suppressed" "SUPPRESSED: concurrency=2" "$RUN_OUT"
assert_not_contains "no paired ratio under concurrency" "median_paired_ratio" "$RUN_OUT"
assert_contains "the per-arm percentiles are still reported" "n=4" "$RUN_OUT"

# --- 3. stdin reaches both arms, and no exit code is fabricated ---
# A `printf | bash -c` pipeline under pipefail reports 141 whenever an arm exits
# without draining stdin, because printf takes EPIPE. The exit-code census would
# then carry a code no arm returned, intermittently.
# discriminating-skip-required: the rc census is the only place a fabricated
# exit code would surface, so this assertion is the whole proof.
# The unread arm is `sleep 0.01`, not `exit 0`: ratio.py fail-closes when every
# comparison-arm sample is 0ms, which `exit 0` records on CI.
# shellcheck disable=SC2016  # $line belongs to the inner `bash -c`, not to this shell
run_ab --a 'read -r line; [[ "$line" == "payload" ]]' --b 'sleep 0.01' \
  --iterations 4 --warmup 0 --stdin 'payload'
assert_eq "a run with stdin exits 0" "0" "$RUN_RC"
assert_contains "the reading arm reports its own exit code" "rc={0: 4}" "$RUN_OUT"
# Match the rc CENSUS, not a bare "141" anywhere in the output. A bare substring
# search collides with timing data: a legitimate 141ms sample printed `min=141ms`
# and failed this assertion for a reason unrelated to what it tests. An exit code
# only ever appears as a dict KEY, so `141:` is the form that means what is meant.
assert_not_contains "an undrained stdin does not fabricate exit code 141" "141:" "$RUN_OUT"
if [[ "$(printf '%s' "$RUN_OUT" | grep -c 'rc={0: 4}')" == "2" ]]; then
  pass "both arms report a clean exit-code census"
else
  fail "both arms report a clean exit-code census" "two rc={0: 4} lines" "$RUN_OUT"
fi

# --- 4. an arm that cannot run is refused before anything is timed ---
run_ab --a "$NOOP" --b "/nonexistent/definitely-not-here" --iterations 2 --warmup 0
assert_eq "an arm exiting 127 is refused" "2" "$RUN_RC"
assert_contains "the refusal names the false-green shape" "classic false green" "$RUN_OUT"

# --- 5. a missing high-resolution clock FAILS, it never falls back to date ---
# PERF_AB_SIMULATE_NO_CLOCK can only force the failure, never suppress it, so
# it cannot turn a genuinely broken host green.
capture env PERF_AB_SIMULATE_NO_CLOCK=1 bash "$AB" --a "$NOOP" --b "$NOOP" --iterations 2
assert_eq "a missing EPOCHREALTIME is refused" "2" "$RUN_RC"
assert_contains "the refusal rejects a date(1) fallback" "Refusing to fall back" "$RUN_OUT"

# A comma-decimal locale renders EPOCHREALTIME as `1788283754,274241`, and the
# microsecond arithmetic then operates on a non-numeric string. Left unguarded
# the run still fails, but downstream and with the wrong diagnosis: the operator
# reads "arm a holds 1 samples" and nothing mentions locale.
# discriminating-skip-required: this case is the only cover for the decimal
# separator, and the simulate seam can only force the failure, never hide one.
capture env PERF_AB_SIMULATE_COMMA_CLOCK=1 bash "$AB" --a "$NOOP" --b "$NOOP" --iterations 2
assert_eq "the simulated comma clock is refused" "2" "$RUN_RC"
# The forced branch must say it is SIMULATING, not assert a locale defect the
# host does not have. A false observation in a test log sends the next reader
# chasing a locale that is working correctly.
assert_contains "the simulated branch declares itself" "SIMULATED:" "$RUN_OUT"
assert_contains "the simulated branch denies a real observation" "No real defect was observed" "$RUN_OUT"
assert_not_contains "the simulated branch does not blame LC_NUMERIC" \
  "is rendering it with a comma" "$RUN_OUT"

# The REAL branch, exercised under an actual comma-decimal locale rather than
# through the seam, so the operator-facing wording is covered by something other
# than the simulation that deliberately does not produce it.
COMMA_LOCALE=""
for candidate in de_DE.UTF-8 de_DE.utf8 de_DE fr_FR.UTF-8 fr_FR.utf8 fr_FR; do
  if [[ "$(LC_ALL="$candidate" bash -c 'printf %s "$EPOCHREALTIME"' 2>/dev/null)" == *,* ]]; then
    COMMA_LOCALE="$candidate"
    break
  fi
done
if [[ -n "$COMMA_LOCALE" ]]; then
  capture env LC_ALL="$COMMA_LOCALE" bash "$AB" --a "$NOOP" --b "$NOOP" --iterations 2
  assert_eq "a real comma-decimal locale is refused" "2" "$RUN_RC"
  assert_contains "the real refusal declines to change the subject's environment" \
    "alter the environment the SUBJECT runs in" "$RUN_OUT"
  # POSIX precedence is LC_ALL > LC_NUMERIC > LANG. Suggesting LC_NUMERIC=C
  # while LC_ALL is set is advice that silently does nothing, so the refusal
  # must name the variable that actually governs THIS invocation.
  # discriminating-skip-required: a refusal whose suggested remedy does not work
  # is worse than no remedy, and only this case proves the remedy is right.
  assert_contains "the refusal names LC_ALL as the overriding variable" \
    "it OVERRIDES LC_NUMERIC" "$RUN_OUT"
  capture env LC_ALL=C bash "$AB" --a "$NOOP" --b "$NOOP" \
    --iterations 2 --warmup 0 --min-pairs 2
  assert_eq "the remedy the refusal names actually runs" "0" "$RUN_RC"

  # And with only LANG set, LC_NUMERIC=C IS the right remedy, so the other
  # branch of the advice must be exercised too.
  capture env -u LC_ALL LANG="$COMMA_LOCALE" bash "$AB" --a "$NOOP" --b "$NOOP" \
    --iterations 2
  if [[ "$RUN_RC" == "2" ]]; then
    assert_contains "with LANG only, the refusal names LC_NUMERIC" "LC_NUMERIC=C" "$RUN_OUT"
    capture env -u LC_ALL LANG="$COMMA_LOCALE" LC_NUMERIC=C bash "$AB" --a "$NOOP" \
      --b "$NOOP" --iterations 2 --warmup 0 --min-pairs 2
    assert_eq "the LANG-only remedy actually runs" "0" "$RUN_RC"
  else
    printf 'SKIP: LANG alone did not produce a comma clock on this host\n' >&2
  fi
else
  printf 'SKIP: no comma-decimal locale on this host; the real-locale arm of the clock check did not run\n' >&2
fi

# --- 6. argument preconditions ---
run_ab --a "$NOOP" --b "$NOOP" --iterations 0
assert_eq "zero iterations is refused" "2" "$RUN_RC"
assert_contains "the refusal explains the empty sample set" "no percentile to report" "$RUN_OUT"

run_ab --a "$NOOP" --b "$NOOP" --iterations many
assert_eq "a non-numeric iteration count is refused" "2" "$RUN_RC"

run_ab --b "$NOOP" --iterations 2
assert_eq "a missing --a is refused" "2" "$RUN_RC"

run_ab --a "bash D:/repo/hook.sh" --b "$NOOP" --iterations 2
assert_eq "a drive-letter path inside an arm command is refused" "2" "$RUN_RC"
assert_contains "the refusal names the 127 shape" "exits 127 in both arms" "$RUN_OUT"

# --- 7. --percentiles reaches both per-arm summaries ---
run_ab --help
assert_contains "--help lists --percentiles" "--percentiles <list>" "$RUN_OUT"

run_ab --a "$NOOP" --b "$NOOP" --iterations 4 --warmup 0 --percentiles 50,99
assert_eq "a --percentiles run exits 0" "0" "$RUN_RC"
if [[ "$(printf '%s' "$RUN_OUT" | grep -c 'p99=REFUSED(n=4<100)')" == "2" ]]; then
  pass "both arms report the listed p99"
else
  fail "both arms report the listed p99" "two p99=REFUSED(n=4<100) cells" "$RUN_OUT"
fi
# The leading space excludes ratio.py's own ratio_of_p95 field.
assert_not_contains "an unlisted p95 is not reported per arm" " p95=" "$RUN_OUT"

run_ab --a "$NOOP" --b "$NOOP" --iterations 2 --warmup 0 --percentiles 0,95
assert_eq "an invalid percentile list is refused" "2" "$RUN_RC"
assert_contains "the refusal names the bad entry" "BENCH_PERCENTILES entry '0'" "$RUN_OUT"

# --- 8. a serial run picks each iteration's arm order at random, and records it ---
# A fixed AB, BA, AB pattern can line up with periodic interference; randomized
# multiple interleaved trials give every round a fresh random order. The rule
# documented in ab.sh: one byte per iteration from PERF_AB_ORDER_SOURCE, even
# runs A first, odd runs B first. The fixture bytes below are chosen by hand, so
# the expected order is derived from that rule, not from running the script.
ORDER_DIR="$(mktemp -d)"
ORDER_FIXTURE="$ORDER_DIR/order-bytes"
ORDER_LOG="$ORDER_DIR/arm-log"
# Bytes 0 1 1 0 3 3 2 4 5 6 7 7 8 10 9 11 12 13 14 14: more than 16, so the
# multi-line read path runs, and with repeats, so a collapsed read would show.
printf '\000\001\001\000\003\003\002\004\005\006\007\007\010\012\011\013\014\015\016\016' >"$ORDER_FIXTURE"
EXPECTED_ORDER="arm_order=AB BA BA AB BA BA AB AB BA AB BA BA AB AB BA BA AB BA AB AB"
# shellcheck disable=SC2016  # $AB_TEST_LOG belongs to the inner `bash -c`, not to this shell
LOG_A='printf A >>"$AB_TEST_LOG"; sleep 0.01'
# shellcheck disable=SC2016  # as above
LOG_B='printf B >>"$AB_TEST_LOG"; sleep 0.01'

run_ordered() {
  : >"$ORDER_LOG"
  capture env AB_TEST_LOG="$ORDER_LOG" PERF_AB_ORDER_SOURCE="$ORDER_FIXTURE" \
    bash "$AB" --a "$LOG_A" --b "$LOG_B" --iterations 20 --warmup 0 --min-pairs 20
}

run_ordered
assert_eq "a run with an order source exits 0" "0" "$RUN_RC"
assert_eq "the order follows the source's bytes, not parity alternation" \
  "$EXPECTED_ORDER" "$(printf '%s\n' "$RUN_OUT" | grep '^arm_order=')"
# The probes run A then B once before any iteration; with no warmup the rest of
# the log is the iterations themselves, so this proves every iteration ran each
# arm exactly once, in the recorded order.
assert_eq "each iteration runs each arm once, in the recorded order" \
  "AB$(printf '%s' "${EXPECTED_ORDER#arm_order=}" | tr -d ' ')" "$(cat "$ORDER_LOG")"

run_ordered
assert_eq "the same order source reproduces the same order" \
  "$EXPECTED_ORDER" "$(printf '%s\n' "$RUN_OUT" | grep '^arm_order=')"

# Too few bytes for the iterations is refused, never padded with a fixed order.
printf '\000\001' >"$ORDER_FIXTURE"
run_ordered
assert_eq "an order source shorter than the iterations is refused" "2" "$RUN_RC"
assert_contains "the refusal names the order source" "PERF_AB_ORDER_SOURCE" "$RUN_OUT"

rm -f "$ORDER_FIXTURE" "$ORDER_LOG"
rmdir "$ORDER_DIR"

# The default source is the OS random device; only the shape is checkable.
run_ab --a "$NOOP" --b "$NOOP" --iterations 6 --warmup 0 --min-pairs 6
assert_eq "a run with the default order source exits 0" "0" "$RUN_RC"
if printf '%s\n' "$RUN_OUT" | grep -Eq '^arm_order=(AB|BA)( (AB|BA)){5}$'; then
  pass "the default source records one AB or BA per iteration"
else
  fail "the default source records one AB or BA per iteration" "arm_order= with 6 tokens" "$RUN_OUT"
fi

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: ab interleaving and refusals"
exit 0
