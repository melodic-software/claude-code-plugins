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

RUN_OUT=""
RUN_RC=0
run_ab() {
  RUN_OUT="$(bash "$AB" "$@" 2>&1)"
  RUN_RC=$?
}

NOOP="printf ok"

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
# shellcheck disable=SC2016  # $line belongs to the inner `bash -c`, not to this shell
run_ab --a 'read -r line; [[ "$line" == "payload" ]]' --b 'exit 0' \
  --iterations 4 --warmup 0 --stdin 'payload'
assert_eq "a run with stdin exits 0" "0" "$RUN_RC"
assert_contains "the reading arm reports its own exit code" "rc={0: 4}" "$RUN_OUT"
assert_not_contains "an undrained stdin does not fabricate rc 141" "141" "$RUN_OUT"

# --- 4. an arm that cannot run is refused before anything is timed ---
run_ab --a "$NOOP" --b "/nonexistent/definitely-not-here" --iterations 2 --warmup 0
assert_eq "an arm exiting 127 is refused" "2" "$RUN_RC"
assert_contains "the refusal names the false-green shape" "classic false green" "$RUN_OUT"

# --- 4. a missing high-resolution clock FAILS, it never falls back to date ---
# PERF_AB_SIMULATE_NO_CLOCK can only force the failure, never suppress it, so
# it cannot turn a genuinely broken host green.
RUN_OUT="$(PERF_AB_SIMULATE_NO_CLOCK=1 bash "$AB" --a "$NOOP" --b "$NOOP" --iterations 2 2>&1)"
RUN_RC=$?
assert_eq "a missing EPOCHREALTIME is refused" "2" "$RUN_RC"
assert_contains "the refusal rejects a date(1) fallback" "Refusing to fall back" "$RUN_OUT"

# A comma-decimal locale renders EPOCHREALTIME as `1788283754,274241`, and the
# microsecond arithmetic then operates on a non-numeric string. Left unguarded
# the run still fails, but downstream and with the wrong diagnosis: the operator
# reads "arm a holds 1 samples" and nothing mentions locale.
# discriminating-skip-required: this case is the only cover for the decimal
# separator, and the simulate seam can only force the failure, never hide one.
RUN_OUT="$(PERF_AB_SIMULATE_COMMA_CLOCK=1 bash "$AB" --a "$NOOP" --b "$NOOP" --iterations 2 2>&1)"
RUN_RC=$?
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
  RUN_OUT="$(LC_ALL="$COMMA_LOCALE" bash "$AB" --a "$NOOP" --b "$NOOP" --iterations 2 2>&1)"
  RUN_RC=$?
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
  RUN_OUT="$(LC_ALL=C bash "$AB" --a "$NOOP" --b "$NOOP" \
    --iterations 2 --warmup 0 --min-pairs 2 2>&1)"
  RUN_RC=$?
  assert_eq "the remedy the refusal names actually runs" "0" "$RUN_RC"

  # And with only LANG set, LC_NUMERIC=C IS the right remedy, so the other
  # branch of the advice must be exercised too.
  RUN_OUT="$(env -u LC_ALL LANG="$COMMA_LOCALE" bash "$AB" --a "$NOOP" --b "$NOOP" \
    --iterations 2 2>&1)"
  RUN_RC=$?
  if [[ "$RUN_RC" == "2" ]]; then
    assert_contains "with LANG only, the refusal names LC_NUMERIC" "LC_NUMERIC=C" "$RUN_OUT"
    RUN_OUT="$(env -u LC_ALL LANG="$COMMA_LOCALE" LC_NUMERIC=C bash "$AB" --a "$NOOP" \
      --b "$NOOP" --iterations 2 --warmup 0 --min-pairs 2 2>&1)"
    RUN_RC=$?
    assert_eq "the LANG-only remedy actually runs" "0" "$RUN_RC"
  else
    printf 'SKIP: LANG alone did not produce a comma clock on this host\n' >&2
  fi
else
  printf 'SKIP: no comma-decimal locale on this host; the real-locale arm of the clock check did not run\n' >&2
fi

# --- 5. argument preconditions ---
run_ab --a "$NOOP" --b "$NOOP" --iterations 0
assert_eq "zero iterations is refused" "2" "$RUN_RC"
assert_contains "the refusal explains the empty sample set" "no percentile to report" "$RUN_OUT"

run_ab --a "$NOOP" --b "$NOOP" --iterations many
assert_eq "a non-numeric iteration count is refused" "2" "$RUN_RC"

run_ab --b "$NOOP" --iterations 2
assert_eq "a missing --a is refused" "2" "$RUN_RC"

run_ab --a "bash D:/repo/hook.sh" --b "$NOOP" --iterations 2
assert_eq "a drive-letter path inside an arm command is refused" "2" "$RUN_RC"
assert_contains "the refusal names the MSYS trap" "resolves nowhere" "$RUN_OUT"

[[ "${FAILED:-0}" -eq 0 ]] || exit 1
echo "OK: ab interleaving and refusals"
exit 0
