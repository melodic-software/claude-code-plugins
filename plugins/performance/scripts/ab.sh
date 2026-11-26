#!/usr/bin/env bash
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
  --percentiles <list>    Per-arm percentiles, comma-separated. Default 50,95.
  --stdin <text>          Feed <text> to both arms on stdin.
  --allow-windows-paths   Permit drive-letter paths in the arm commands.

  PERF_AB_ORDER_SOURCE    File the serial run reads its arm order from, one
                          byte per iteration: even runs A first, odd runs B
                          first. Default /dev/urandom; the same file gives
                          the same order.

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
PERCENTILES="50,95"
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
    --percentiles)
      PERCENTILES="${2:-}"
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

if [[ -n "${PERF_AB_SIMULATE_NO_CLOCK:-}" || -z "${EPOCHREALTIME:-}" ]]; then
  harness_die "EPOCHREALTIME is unavailable, so this shell has no spawn-free high-resolution clock (bash 5.0 or later provides it). Refusing to fall back to date(1): a process spawn per sample would measure the harness alongside the subject."
fi

if [[ -n "${PERF_AB_SIMULATE_COMMA_CLOCK:-}" ]]; then
  harness_die "SIMULATED: PERF_AB_SIMULATE_COMMA_CLOCK is set, so this run forces the comma-decimal-separator refusal. No real defect was observed; EPOCHREALTIME actually reads '${EPOCHREALTIME}'. Unset the variable to measure normally."
fi
if [[ "$EPOCHREALTIME" != *.* ]]; then
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

STDIN_PATH="$OUT/stdin"
printf '%s' "$STDIN_TEXT" >"$STDIN_PATH"

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
  ORDER_SOURCE="${PERF_AB_ORDER_SOURCE:-/dev/urandom}"
  order_bytes=()
  read -r -d '' -a order_bytes < <(od -An -v -tu1 -N"$ITERS" "$ORDER_SOURCE" 2>/dev/null)
  if ((${#order_bytes[@]} != ITERS)); then
    harness_die "the order source '$ORDER_SOURCE' (PERF_AB_ORDER_SOURCE) yielded ${#order_bytes[@]} bytes; $ITERS iterations need one byte each."
  fi
  order=()
  for ((i = 0; i < ITERS; i++)); do
    if ((order_bytes[i] % 2 == 0)); then
      one "$CMD_A" "$OUT/a"
      one "$CMD_B" "$OUT/b"
      order+=(AB)
    else
      one "$CMD_B" "$OUT/b"
      one "$CMD_A" "$OUT/a"
      # The label on the next line is an arm-order label, not a misspelling.
      order+=(BA) # spellchecker:disable-line
    fi
  done
  printf 'arm_order=%s\n' "${order[*]}"
else
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

BENCH_LABEL="$LABEL_A" BENCH_CONC="$CONC" BENCH_TIMES="$OUT/a" BENCH_PERCENTILES="$PERCENTILES" \
  "$HARNESS_PYTHON" "$SCRIPT_DIR/summarize.py" || exit $?
BENCH_LABEL="$LABEL_B" BENCH_CONC="$CONC" BENCH_TIMES="$OUT/b" BENCH_PERCENTILES="$PERCENTILES" \
  "$HARNESS_PYTHON" "$SCRIPT_DIR/summarize.py" || exit $?

BENCH_OLD="$OUT/a" BENCH_NEW="$OUT/b" BENCH_CONC="$CONC" BENCH_MIN_PAIRS="$MIN_PAIRS" \
  "$HARNESS_PYTHON" "$SCRIPT_DIR/ratio.py" || exit $?
