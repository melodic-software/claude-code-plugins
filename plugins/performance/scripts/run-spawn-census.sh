#!/usr/bin/env bash
# Before/after spawn census, with the rule-1 self-proof built in.
#
# harness-integrity.md rule 1: run the harness twice against an UNCHANGED
# subject; if the two runs disagree beyond characterized noise, the harness is a
# variable rather than an instrument. A spawn count has no noise band, so the
# runs must agree exactly, and a disagreement is a hard failure here rather than
# a footnote in the report.
#
# The comparison is between WARM runs only. Run 1 of each arm is discarded as
# cold and reported separately: a cold cache legitimately changes a spawn count,
# and a gate that fired on that would be loosened by the next person to hit it.
#
# Usage:
#   run-spawn-census.sh --shim-dir <dir> --before <command> --after <command> [options]
#
#   --shim-dir <dir>        REQUIRED. Passed through to spawn-census.sh.
#   --before <command>      REQUIRED. Shell command string for the baseline arm.
#   --after <command>       REQUIRED. Shell command string for the changed arm.
#   --before-label <s>      Default: before
#   --after-label <s>       Default: after
#   --warm <n>              Warm runs per arm, all of which must agree. Default 2.
#   --reset-command <cmd>   Run once up front, for a targeted cache reset.
#   --tool <name>           Passed through. Repeatable.
#   --stdin <text>          Passed through.
#   --stdin-file <path>     Passed through.
#   --allow-windows-paths   Passed through.
#
# Exit: 0 both arms were stable; 2 a precondition failed, including an arm whose
# warm runs disagreed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
# shellcheck source=harness-lib.sh
source "$SCRIPT_DIR/harness-lib.sh"

CENSUS="$SCRIPT_DIR/spawn-census.sh"

usage() {
  cat <<'USAGE'
run-spawn-census.sh --shim-dir <dir> --before <command> --after <command> [options]

  --shim-dir <dir>        REQUIRED. Passed through to spawn-census.sh.
  --before <command>      REQUIRED. Shell command string for the baseline arm.
  --after <command>       REQUIRED. Shell command string for the changed arm.
  --before-label <s>      Default: before
  --after-label <s>       Default: after
  --warm <n>              Warm runs per arm, all of which must agree. Default 2.
  --reset-command <cmd>   Run once up front, for a targeted cache reset.
  --tool <name>           Passed through. Repeatable.
  --stdin <text>          Passed through.
  --stdin-file <path>     Passed through.
  --allow-windows-paths   Passed through.

Exit: 0 both arms stable; 2 a precondition failed (including disagreeing warm runs).
USAGE
}

SHIM_DIR=""
BEFORE_COMMAND=""
AFTER_COMMAND=""
BEFORE_LABEL="before"
AFTER_LABEL="after"
WARM=2
RESET_COMMAND=""
PASSTHROUGH=()
HAVE_BEFORE=0
HAVE_AFTER=0

while (($# > 0)); do
  case "$1" in
    --shim-dir)
      SHIM_DIR="${2:-}"
      shift 2
      ;;
    --before)
      BEFORE_COMMAND="${2:-}"
      HAVE_BEFORE=1
      shift 2
      ;;
    --after)
      AFTER_COMMAND="${2:-}"
      HAVE_AFTER=1
      shift 2
      ;;
    --before-label)
      BEFORE_LABEL="${2:-}"
      shift 2
      ;;
    --after-label)
      AFTER_LABEL="${2:-}"
      shift 2
      ;;
    --warm)
      WARM="${2:-}"
      shift 2
      ;;
    --reset-command)
      RESET_COMMAND="${2:-}"
      shift 2
      ;;
    --tool)
      PASSTHROUGH+=(--tool "${2:-}")
      shift 2
      ;;
    --stdin)
      PASSTHROUGH+=(--stdin "${2:-}")
      shift 2
      ;;
    --stdin-file)
      PASSTHROUGH+=(--stdin-file "${2:-}")
      shift 2
      ;;
    --allow-windows-paths)
      PASSTHROUGH+=(--allow-windows-paths)
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

((HAVE_BEFORE == 1)) || harness_die "--before is required: a shell command string for the baseline arm."
((HAVE_AFTER == 1)) || harness_die "--after is required: a shell command string for the changed arm."
[[ -x "$CENSUS" || -f "$CENSUS" ]] || harness_die "spawn-census.sh not found beside this script: $CENSUS"

if [[ ! "$WARM" =~ ^[0-9]+$ ]] || ((WARM < 2)); then
  harness_die "--warm must be an integer of at least 2. The whole point is comparing two warm runs against an unchanged subject; one run can agree with nothing."
fi

if [[ -n "$RESET_COMMAND" ]]; then
  bash -c "$RESET_COMMAND" || harness_die "the reset command failed: $RESET_COMMAND"
fi

CENSUS_COUNT=""

# Sets CENSUS_COUNT. Not a $( ) helper, so a precondition
# failure inside spawn-census.sh can terminate this script rather than a
# subshell nobody is checking.
census_run() {
  local label="$1" command="$2" rc=0 line=""
  set +e
  line="$(bash "$CENSUS" --shim-dir "$SHIM_DIR" --label "$label" --ledger-key "$label" \
    "${PASSTHROUGH[@]}" -- bash -c "$command" 2>&1)"
  rc=$?
  set -e
  ((rc == 0)) || harness_die "the census failed for arm '$label' (exit $rc). Its output was: $line"
  [[ "$line" == *spawns=* ]] || harness_die "the census produced no spawns= field for arm '$label'. Its output was: $line"
  CENSUS_COUNT="${line#*spawns=}"
  CENSUS_COUNT="${CENSUS_COUNT%%[[:space:]]*}"
}

ARM_WARM=""

run_arm() {
  local label="$1" command="$2"
  local cold="" warm_first="" i
  census_run "$label" "$command"
  cold="$CENSUS_COUNT"
  printf '%-14s cold  spawns=%s\n' "$label" "$cold"

  for ((i = 1; i <= WARM; i++)); do
    census_run "$label" "$command"
    printf '%-14s warm%-2s spawns=%s\n' "$label" "$i" "$CENSUS_COUNT"
    if [[ -z "$warm_first" ]]; then
      warm_first="$CENSUS_COUNT"
    elif [[ "$CENSUS_COUNT" != "$warm_first" ]]; then
      harness_die "arm '$label' counted $warm_first and $CENSUS_COUNT spawns on two WARM runs against an UNCHANGED subject. harness-integrity.md rule 1: two runs against an unchanged subject must agree, or the harness is a variable rather than an instrument. Run 1 was discarded as cold, so this is not a cold-cache artifact. Do not report a before/after delta from this harness until it is stable."
    fi
  done
  ARM_WARM="$warm_first"
}

run_arm "$BEFORE_LABEL" "$BEFORE_COMMAND"
before_warm="$ARM_WARM"
run_arm "$AFTER_LABEL" "$AFTER_COMMAND"
after_warm="$ARM_WARM"

printf 'COUNTER        %s=%s -> %s=%s  delta=%s\n' \
  "$BEFORE_LABEL" "$before_warm" "$AFTER_LABEL" "$after_warm" \
  "$((after_warm - before_warm))"
printf 'STABILITY      both arms agreed across %s warm runs each (harness-integrity.md rule 1)\n' "$WARM"
