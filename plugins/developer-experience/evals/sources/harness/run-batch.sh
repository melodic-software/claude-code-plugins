#!/usr/bin/env bash
# Run a list of eval runs through run-cell.sh, up to N at a time.
set -uo pipefail

usage() {
  cat <<'EOF'
run-batch.sh: run eval runs from a list, in parallel.

Usage: run-batch.sh --list FILE --model MODEL --budget CAP [--jobs N] [--log-dir DIR]
       run-batch.sh --help

  --list     file of lines "SCENARIO ARM RUN" (blank lines and # comments skipped)
  --jobs     concurrent runs (default 4)
  --log-dir  where each run's stdout/stderr log goes (default: the list file's directory)

Prints one VALID/INVALID line per run. Exit: 0 every run valid; 1 any run invalid
or refused; 2 usage.
EOF
}

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="" MODEL="" BUDGET="" JOBS=4 LOG_DIR=""
while (($#)); do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --list | --model | --budget | --jobs | --log-dir)
      (($# >= 2)) || {
        echo "run-batch: $1 needs a value" >&2
        exit 2
      }
      case "$1" in
        --list) LIST="$2" ;;
        --model) MODEL="$2" ;;
        --budget) BUDGET="$2" ;;
        --jobs) JOBS="$2" ;;
        *) LOG_DIR="$2" ;;
      esac
      shift 2
      ;;
    *)
      echo "run-batch: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done
[[ -f "$LIST" && -n "$MODEL" && -n "$BUDGET" && "$JOBS" =~ ^[1-9][0-9]*$ ]] || {
  echo "run-batch: --list FILE, --model and --budget are required (see --help)" >&2
  exit 2
}
LOG_DIR="${LOG_DIR:-$(dirname "$LIST")}"
mkdir -p "$LOG_DIR"

export HARNESS_DIR MODEL BUDGET LOG_DIR
# shellcheck disable=SC2016
grep -Ev '^\s*(#|$)' "$LIST" | xargs -P "$JOBS" -L 1 bash -c '
  log="$LOG_DIR/$0-$1-$MODEL-run$2.log"
  if "$HARNESS_DIR/run-cell.sh" --scenario "$0" --arm "$1" --model "$MODEL" --run "$2" --budget "$BUDGET" >"$log" 2>&1; then
    echo "VALID $0 $1 run-$2"
  else
    echo "INVALID $0 $1 run-$2 (see $log)"
    exit 1
  fi'
