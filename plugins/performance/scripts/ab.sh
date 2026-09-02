#!/usr/bin/env bash
# INTERLEAVED before/after timing for two arbitrary commands.
#
# Never compare two separate passes on a drifting host. A bare `bash -c true`
# measured 1825ms and 283ms in the same hour at roughly 10% CPU on the box this
# plugin was built from; any two-pass comparison attributes that 6x to the
# change. Alternating the arms within a single run, and flipping the ORDER each
# iteration, puts both arms under the same instantaneous load, so the paired
# ratio survives drift the absolute numbers do not.
#
# Grounded, Tier 1, benchstat's own documentation: "The best way to do this is
# to interleave before and after runs, rather than running, say, 10 iterations
# of the before benchmark, and then 10 iterations of the after benchmark."
#
# Under CONCURRENCY the paired ratio is SUPPRESSED, not merely caveated. The
# arms interleave arbitrarily once they overlap, so pairing by index compares
# samples that never shared conditions. ratio.py enforces that refusal itself,
# so a caller who invokes it directly cannot lose the suppression.
#
# Usage:
#   ab.sh --a <command> --b <command> --iterations <n> [options]
#
#   --a <command>           REQUIRED. Baseline arm, a shell command string.
#   --b <command>           REQUIRED. Comparison arm, a shell command string.
#   --iterations <n>        REQUIRED. Paired iterations, at least 1.
#   --concurrency <c>       Parallel writers. Default 1. Above 1 suppresses the ratio.
#   --label-a <s>           Default: A (baseline)
#   --label-b <s>           Default: B (candidate)
#   --warmup <n>            Discard this many runs per arm first. Default 1.
#   --min-pairs <n>         Pairs required before a ratio is reported. Default 20.
#   --stdin <text>          Feed <text> to both arms on stdin.
#   --allow-windows-paths   Permit drive-letter paths in the arm commands.
#
# Exit: 0 the run completed; 1 a sample-count assertion failed; 2 a precondition
# failed.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"

usage() {
  cat <<'USAGE'
ab.sh --a <command> --b <command> --iterations <n> [options]

  --a <command>           REQUIRED. Baseline arm, a shell command string.
  --b <command>           REQUIRED. Comparison arm, a shell command string.
  --iterations <n>        REQUIRED. Paired iterations, at least 1.
  --concurrency <c>       Parallel writers. Default 1. Above 1 suppresses the ratio.
  --label-a <s>           Default: A (baseline)
  --label-b <s>           Default: B (candidate)
  --warmup <n>            Discard this many runs per arm first. Default 1.
  --min-pairs <n>         Pairs required before a ratio is reported. Default 20.
  --stdin <text>          Feed <text> to both arms on stdin.
  --allow-windows-paths   Permit drive-letter paths in the arm commands.

Exit: 0 completed; 1 a sample-count assertion failed; 2 a precondition failed.
USAGE
}

CMD_A=""
CMD_B=""
ITERS=""
CONC=1
LABEL_A="A (baseline)"
LABEL_B="B (candidate)"
WARMUP=1
MIN_PAIRS="20"
STDIN_TEXT=""
ALLOW_WINDOWS_PATHS=0

while (($# > 0)); do
  case "$1" in
    --a)
      CMD_A="${2:-}"
      shift 2
      ;;
    --b)
      CMD_B="${2:-}"
      shift 2
      ;;
    --iterations)
      ITERS="${2:-}"
      shift 2
      ;;
    --concurrency)
      CONC="${2:-}"
      shift 2
      ;;
    --label-a)
      LABEL_A="${2:-}"
      shift 2
      ;;
    --label-b)
      LABEL_B="${2:-}"
      shift 2
      ;;
    --warmup)
      WARMUP="${2:-}"
      shift 2
      ;;
    --min-pairs)
      MIN_PAIRS="${2:-}"
      shift 2
      ;;
    --stdin)
      STDIN_TEXT="${2:-}"
      shift 2
      ;;
    --allow-windows-paths)
      ALLOW_WINDOWS_PATHS=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      harness_die "unknown argument: $1 (see --help)"
      ;;
  esac
done

# A missing high-resolution clock must FAIL, never fall back to `date`. A
# per-sample date(1) call is a process spawn, so the fallback would measure the
# instrument at roughly the same magnitude as the subject and report it as the
# subject's cost. harness-integrity.md rule 2: assert the precondition, do not
# degrade into a weaker measurement that passes.
#
# PERF_AB_SIMULATE_NO_CLOCK exists so the suite can exercise this branch on a
# host that does have the clock. It can only FORCE the failure, never suppress
# it, so it cannot turn a broken host green.
if [[ -n "${PERF_AB_SIMULATE_NO_CLOCK:-}" || -z "${EPOCHREALTIME:-}" ]]; then
  harness_die "EPOCHREALTIME is unavailable, so this shell has no spawn-free high-resolution clock (bash 5.0 or later provides it). Refusing to fall back to date(1): a process spawn per sample would measure the harness alongside the subject."
fi

# EPOCHREALTIME honors LC_NUMERIC, so a comma-decimal locale renders it as
# `1788283754,274241`. The microsecond split below then feeds a non-numeric
# string to base-10 arithmetic. That failure is caught downstream by the
# sample-count assertion, but it is caught with the wrong diagnosis, and the
# operator is left reading "arm a holds 1 samples" with no hint about locale.
# Refused here, by name. Deliberately NOT auto-corrected: forcing LC_NUMERIC
# would change the environment the SUBJECT runs in, which is the one thing rule 1
# says a harness must not do quietly. Re-run with LC_NUMERIC=C if that is what
# you want, and record it.
#
# PERF_AB_SIMULATE_COMMA_CLOCK, like the seam above, can only FORCE this failure,
# never suppress it, so it cannot turn a broken host green.
if [[ -n "${PERF_AB_SIMULATE_COMMA_CLOCK:-}" ]]; then
  # The simulated branch must NOT assert the real observation, because the real
  # observation is fine. A forced failure that claims a locale defect the host
  # does not have sends the next reader chasing a working locale.
  harness_die "SIMULATED: PERF_AB_SIMULATE_COMMA_CLOCK is set, so this run forces the comma-decimal-separator refusal. No real defect was observed; EPOCHREALTIME actually reads '${EPOCHREALTIME}'. Unset the variable to measure normally."
fi
if [[ "$EPOCHREALTIME" != *.* ]]; then
  # Name the variable that ACTUALLY governs. POSIX precedence is
  # LC_ALL > LC_NUMERIC > LANG, so telling someone to set LC_NUMERIC=C while
  # LC_ALL is set is advice that silently does nothing: verified here, with
  # LC_ALL=de_DE.UTF-8 the clock still reads a comma no matter what LC_NUMERIC
  # says. A refusal whose suggested fix does not work is worse than no fix.
  if [[ -n "${LC_ALL:-}" ]]; then
    remedy="LC_ALL is set to '${LC_ALL}', and it OVERRIDES LC_NUMERIC, so setting LC_NUMERIC=C alone will not help. Re-run with LC_ALL=C, or unset LC_ALL and set LC_NUMERIC=C"
  else
    remedy="Re-run with LC_NUMERIC=C (currently '${LC_NUMERIC:-${LANG:-unset}}')"
  fi
  harness_die "EPOCHREALTIME reads '${EPOCHREALTIME}', which has no '.' decimal separator, so the microsecond arithmetic here would operate on a non-numeric string. ${remedy}, and record in the report that you changed the locale. This harness will not change it for you: that would alter the environment the SUBJECT runs in."
fi

[[ -n "$CMD_A" ]] || harness_die "--a is required: a shell command string for the baseline arm."
[[ -n "$CMD_B" ]] || harness_die "--b is required: a shell command string for the comparison arm."
[[ "$ITERS" =~ ^[0-9]+$ ]] || harness_die "--iterations must be a non-negative integer, got '${ITERS:-<unset>}'."
((ITERS >= 1)) || harness_die "--iterations must be at least 1; there is no percentile to report from zero samples."
if [[ ! "$CONC" =~ ^[0-9]+$ ]] || ((CONC < 1)); then
  harness_die "--concurrency must be an integer of at least 1, got '$CONC'."
fi
[[ "$WARMUP" =~ ^[0-9]+$ ]] || harness_die "--warmup must be a non-negative integer, got '$WARMUP'."

if ((ALLOW_WINDOWS_PATHS == 0)); then
  harness_require_posix_path "the --a command" "$CMD_A"
  harness_require_posix_path "the --b command" "$CMD_B"
fi

harness_require_python

OUT="$(mktemp -d)"
readonly OUT
trap 'rm -rf "$OUT"' EXIT

: >"$OUT/a"
: >"$OUT/b"

# Stdin is materialized ONCE and redirected, never piped per sample. A
# `printf ... | bash -c` pipeline under `pipefail` reports 141 whenever the arm
# exits without draining stdin, because printf takes EPIPE and is then the only
# non-zero element: the exit-code census would carry a code the arm never
# returned, intermittently, on a pipe-buffer race. The pipeline also forks a
# subshell per sample, and a process spawn costs roughly 140ms on this class of
# host, so it would inflate every absolute number this script reports.
STDIN_PATH="$OUT/stdin"
printf '%s' "$STDIN_TEXT" >"$STDIN_PATH"

# One timed invocation. Deliberately arithmetic-only after the clock reads:
# every command substitution is itself a process spawn under MSYS, so a
# converter that shelled out would add the very cost being measured.
one() {
  local command="$1" sink="$2"
  local t0 t1 rc
  t0=$EPOCHREALTIME
  bash -c "$command" <"$STDIN_PATH" >/dev/null 2>&1
  rc=$?
  t1=$EPOCHREALTIME
  local s0="${t0%%.*}" u0="${t0##*.}" s1="${t1%%.*}" u1="${t1##*.}"
  printf '%s %s\n' "$(((s1 - s0) * 1000 + (10#$u1 - 10#$u0) / 1000))" "$rc" >>"$sink"
}

# Probe both arms before measuring anything. Two arms that both exit 127 produce
# a tidy, symmetric, entirely meaningless comparison, which is the shape four of
# the five source-run harnesses shipped.
probe() {
  local label="$1" command="$2"
  bash -c "$command" <"$STDIN_PATH" >/dev/null 2>&1
  local rc=$?
  if ((rc == 127)); then
    harness_die "arm $label exited 127 (command not found): $command. Both arms failing identically is the classic false green; refusing to time a command that never runs."
  fi
}

probe "$LABEL_A" "$CMD_A"
probe "$LABEL_B" "$CMD_B"

for ((w = 0; w < WARMUP; w++)); do
  one "$CMD_A" /dev/null
  one "$CMD_B" /dev/null
done

if [[ "$CONC" == "1" ]]; then
  for ((i = 0; i < ITERS; i++)); do
    # Flip the ORDER each iteration so neither arm systematically lands in the
    # warmer or colder half of a drift cycle.
    if ((i % 2 == 0)); then
      one "$CMD_A" "$OUT/a"
      one "$CMD_B" "$OUT/b"
    else
      one "$CMD_B" "$OUT/b"
      one "$CMD_A" "$OUT/a"
    fi
  done
else
  # One sink file PER ITERATION. Parallel appends to a single file are not
  # atomic on MSYS, and a spliced line makes the summarizer raise on a value
  # that was never measured. Concatenate after every writer has exited.
  mkdir -p "$OUT/parts"
  for ((i = 0; i < ITERS; i++)); do
    { one "$CMD_A" "$OUT/parts/a-$i"; } &
    { one "$CMD_B" "$OUT/parts/b-$i"; } &
    while (($(jobs -rp | wc -l) >= CONC)); do wait -n; done
  done
  wait
  cat "$OUT/parts"/a-* >"$OUT/a"
  cat "$OUT/parts"/b-* >"$OUT/b"
fi

for arm in a b; do
  lines="$(grep -c . "$OUT/$arm" || true)"
  if [[ "$lines" != "$ITERS" ]]; then
    printf 'FATAL: arm %s holds %s samples, expected %s. Refusing to summarize a sample set that lost or gained rows.\n' \
      "$arm" "$lines" "$ITERS" >&2
    exit 1
  fi
done

BENCH_LABEL="$LABEL_A" BENCH_CONC="$CONC" BENCH_TIMES="$OUT/a" \
  "$HARNESS_PYTHON" "$SCRIPT_DIR/summarize.py" || exit $?
BENCH_LABEL="$LABEL_B" BENCH_CONC="$CONC" BENCH_TIMES="$OUT/b" \
  "$HARNESS_PYTHON" "$SCRIPT_DIR/summarize.py" || exit $?

BENCH_OLD="$OUT/a" BENCH_NEW="$OUT/b" BENCH_CONC="$CONC" BENCH_MIN_PAIRS="$MIN_PAIRS" \
  "$HARNESS_PYTHON" "$SCRIPT_DIR/ratio.py" || exit $?
