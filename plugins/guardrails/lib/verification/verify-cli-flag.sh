#!/usr/bin/env bash
# Exit codes:
#   0  Flag exists in `<bin> [<subcmd>...] --help` output, or in the help
#      that lists the bin's global arguments (az: `az version --help`)
#   1  Flag absent — likely hallucinated
#   2  Binary missing on PATH OR `<bin> --help` failed (cannot verify)
#   3  Argument validation error (caller bug)

set -uo pipefail

CFV_LIB_DIR="${BASH_SOURCE[0]%/*}"
[[ "$CFV_LIB_DIR" == "${BASH_SOURCE[0]}" ]] && CFV_LIB_DIR=.
# shellcheck source=cli-flag-cache.sh
source "$CFV_LIB_DIR/cli-flag-cache.sh"

usage() {
  cat <<'EOF'
Verify whether a CLI flag exists by parsing `<bin> [<subcmd>...] --help`.

Usage: verify-cli-flag.sh [OPTIONS] <bin> [<subcmd>...] --<flag>

Options (recognized only before <bin>):
  -h, --help        Print usage and exit 0
  --quiet           Suppress non-error output
  --verbose         Print the matching --help line on success
  --                End of verifier options

Exit codes:
  0  Flag exists in the --help output (or the bin's global-arguments help)
  1  Flag absent
  2  Binary missing on PATH or `<bin> --help` failed (cannot verify)
  3  Argument validation error
EOF
}

QUIET=false
VERBOSE=false

while (($# > 0)); do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --quiet)
    QUIET=true
    shift
    ;;
  --verbose)
    VERBOSE=true
    shift
    ;;
  --)
    shift
    break
    ;;
  *) break ;;
  esac
done

if (($# < 2)); then
  echo "verify-cli-flag: error: expected <bin> [<subcmd>...] --<flag>" >&2
  echo "Run with --help for usage." >&2
  exit 3
fi

FLAG="${!#}"
if [[ "$FLAG" != --* ]]; then
  echo "verify-cli-flag: error: last argument must start with '--' (got '$FLAG')" >&2
  exit 3
fi

FLAG_NAME="${FLAG%%=*}"

BIN="$1"
SUBCMDS=("${@:2:$#-2}")

if ! command -v "$BIN" >/dev/null 2>&1; then
  $QUIET || echo "verify-cli-flag: '$BIN' not found on PATH" >&2
  exit 2
fi

CACHE_DIR=""
cfv_cache_dir_to CACHE_DIR
[[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR" 2>/dev/null || true

CACHE_KEY=""
cfv_cache_key_to CACHE_KEY "$BIN" "${SUBCMDS[@]}"
CACHE_FILE="$CACHE_DIR/$CACHE_KEY.help"

USE_CACHE=false
if [[ -s "$CACHE_FILE" ]]; then
  FRESH_REF="$CACHE_DIR/.fresh-24h"
  if [[ -n "${EPOCHSECONDS:-}" ]] &&
    printf -v FRESH_STAMP '%(%Y%m%d%H%M.%S)T' "$((EPOCHSECONDS - CFV_CACHE_WINDOW_MIN * 60))" 2>/dev/null &&
    touch -t "$FRESH_STAMP" "$FRESH_REF" 2>/dev/null; then
    [[ "$CACHE_FILE" -nt "$FRESH_REF" ]] && USE_CACHE=true
  elif grep -q . < <(find "$CACHE_FILE" -mmin "-$CFV_CACHE_WINDOW_MIN" 2>/dev/null); then
    USE_CACHE=true
  fi
fi

HELP_OUTPUT=""
if $USE_CACHE; then
  HELP_OUTPUT=$(<"$CACHE_FILE")
else
  TIMEOUT_PREFIX=()
  command -v timeout >/dev/null 2>&1 && TIMEOUT_PREFIX=(timeout 5)
  HELP_OUTPUT=$("${TIMEOUT_PREFIX[@]}" "$BIN" "${SUBCMDS[@]}" --help 2>&1)
  HELP_RC=$?
  if [[ -z "$HELP_OUTPUT" ]] || ((HELP_RC == 124)); then
    $QUIET || echo "verify-cli-flag: '$BIN ${SUBCMDS[*]} --help' failed (rc=$HELP_RC, empty/timeout)" >&2
    exit 2
  fi
  CACHE_TMP="$CACHE_FILE.$$.tmp"
  printf '%s' "$HELP_OUTPUT" >"$CACHE_TMP" 2>/dev/null && mv -f "$CACHE_TMP" "$CACHE_FILE" 2>/dev/null ||
    rm -f "$CACHE_TMP" 2>/dev/null || true
fi

FLAG_PATTERN=""
cfv_flag_pattern_to FLAG_PATTERN "$FLAG_NAME"
if [[ "$HELP_OUTPUT" =~ $FLAG_PATTERN ]]; then
  $VERBOSE && grep -m 1 -nE "$FLAG_PATTERN" < <(printf '%s\n' "$HELP_OUTPUT")
  exit 0
fi

GLOBAL_CHAIN=""
cfv_global_chain_to GLOBAL_CHAIN "$BIN"
if [[ -n "$GLOBAL_CHAIN" && "${SUBCMDS[*]}" != "$GLOBAL_CHAIN" ]]; then
  GLOBAL_OPTS=(--quiet)
  $VERBOSE && GLOBAL_OPTS+=(--verbose)
  bash "${BASH_SOURCE[0]}" "${GLOBAL_OPTS[@]}" -- "$BIN" "$GLOBAL_CHAIN" "$FLAG_NAME" && exit 0
fi

$QUIET || echo "verify-cli-flag: '$FLAG_NAME' not found in '$BIN ${SUBCMDS[*]} --help' output" >&2
exit 1
