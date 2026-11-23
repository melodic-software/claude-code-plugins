#!/usr/bin/env bash
# Verify whether a CLI flag exists by parsing `<bin> [<subcmd>...] --help`.
# Deterministic primitive used by:
#   - Agents (callable inline before editing scripts that reference CLI flags)
#   - The cli-flag-verify PostToolUse hook (file-write detection)
#
# Usage:
#   verify-cli-flag.sh [OPTIONS] <bin> [<subcmd>...] --<flag>
#
# Options (recognized only BEFORE <bin>; a target flag named --quiet or
# --verbose is therefore never consumed as a verifier option):
#   -h, --help        Print usage and exit 0
#   --quiet           Suppress non-error output
#   --verbose         Print the matching --help line on success
#   --                End of verifier options
#
# Arguments:
#   <bin>             Binary name on PATH (e.g. claude, gh, dotnet)
#   <subcmd>...       Optional subcommand chain (e.g. gh pr create)
#   --<flag>          The flag to verify (must start with `--`)
#
# Exit codes:
#   0  Flag exists in `<bin> [<subcmd>...] --help` output, or in the help
#      that lists the bin's global arguments (az: `az version --help`)
#   1  Flag absent — likely hallucinated
#   2  Binary missing on PATH OR `<bin> --help` failed (cannot verify)
#   3  Argument validation error (caller bug)
#
# Cross-platform: Git Bash on Windows + Linux + macOS bash 5.x.
# Caches `--help` output per-binary in $LOCALAPPDATA/guardrails or $XDG_CACHE_HOME/guardrails.

set -uo pipefail

CFV_LIB_DIR="${BASH_SOURCE[0]%/*}"
[[ "$CFV_LIB_DIR" == "${BASH_SOURCE[0]}" ]] && CFV_LIB_DIR=.
# shellcheck source=cli-flag-cache.sh
source "$CFV_LIB_DIR/cli-flag-cache.sh"

usage() {
  sed -n '2,/^$/{s/^# \{0,1\}//;p;}' "${BASH_SOURCE[0]}"
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
  # Some CLIs return non-zero on --help (e.g. busybox tools, malformed args).
  # Tolerate non-zero as long as output is non-empty and it did not time out.
  if [[ -z "$HELP_OUTPUT" ]] || ((HELP_RC == 124)); then
    $QUIET || echo "verify-cli-flag: '$BIN ${SUBCMDS[*]} --help' failed (rc=$HELP_RC, empty/timeout)" >&2
    exit 2
  fi
  # Persist to cache (best-effort), published by rename. Concurrent hooks race
  # to refresh one key, and bash's printf to a file is many write(2) calls, not
  # one, so a reader that passes the -s and mtime gates mid-rewrite would read
  # a prefix and report a documented flag as unknown. `mv` is atomic within a
  # filesystem: the reader sees the previous whole text or the new whole text.
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
