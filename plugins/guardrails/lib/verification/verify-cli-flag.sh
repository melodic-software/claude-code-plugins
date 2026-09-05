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
#   0  Flag exists in `<bin> [<subcmd>...] --help` output
#   1  Flag absent — likely hallucinated
#   2  Binary missing on PATH OR `<bin> --help` failed (cannot verify)
#   3  Argument validation error (caller bug)
#
# Cross-platform: Git Bash on Windows + Linux + macOS bash 5.x.
# Caches `--help` output per-binary in $LOCALAPPDATA/guardrails or $XDG_CACHE_HOME/guardrails.

# Omit -e: we explicitly capture exit codes from `<bin> --help` and decide.
set -uo pipefail

# Cache location, key, window and flag pattern are shared with the
# cli-flag-verify hook, which answers cache hits without spawning this script.
CFV_LIB_DIR="${BASH_SOURCE[0]%/*}"
[[ "$CFV_LIB_DIR" == "${BASH_SOURCE[0]}" ]] && CFV_LIB_DIR=.
# shellcheck source=cli-flag-cache.sh
source "$CFV_LIB_DIR/cli-flag-cache.sh"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

QUIET=false
VERBOSE=false

# Verifier options are recognized only at the FRONT of argv; parsing stops at
# the first positional so a TARGET flag spelled --quiet/--verbose stays a
# positional and gets verified instead of silently steering the verifier.
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

ARGS=("$@")

if ((${#ARGS[@]} < 2)); then
  echo "verify-cli-flag: error: expected <bin> [<subcmd>...] --<flag>" >&2
  echo "Run with --help for usage." >&2
  exit 3
fi

# Last positional must be a --flag token. Everything before it is bin+subcmds.
FLAG="${ARGS[-1]}"
if [[ "$FLAG" != --* ]]; then
  echo "verify-cli-flag: error: last argument must start with '--' (got '$FLAG')" >&2
  exit 3
fi

# Strip trailing =VALUE if present (e.g. --output-format=json).
FLAG_NAME="${FLAG%%=*}"

unset 'ARGS[-1]'
BIN="${ARGS[0]}"
unset 'ARGS[0]'
# Remaining ARGS are subcommands. Empty array if none.
SUBCMDS=("${ARGS[@]}")

# Verify binary on PATH.
if ! command -v "$BIN" >/dev/null 2>&1; then
  $QUIET || echo "verify-cli-flag: '$BIN' not found on PATH" >&2
  exit 2
fi

# Cache directory and key come from the shared definitions (cli-flag-cache.sh).
CACHE_DIR=""
cfv_cache_dir_to CACHE_DIR
# The directory exists on every run but the first; a test costs nothing and a
# spawn costs a process (a fork emulation on Windows Git Bash).
[[ -d "$CACHE_DIR" ]] || mkdir -p "$CACHE_DIR" 2>/dev/null || true

CACHE_KEY=""
cfv_cache_key_to CACHE_KEY "$BIN" "${SUBCMDS[@]}"
CACHE_FILE="$CACHE_DIR/$CACHE_KEY.help"

# Cache hit if file exists, mtime within 24h, non-empty. The 24 h mark is a
# reference file touched to that timestamp and compared with bash's own `-nt`:
# one `touch` (POSIX `-t`) in place of `find | grep`, which cost two processes
# plus the pipe. Bash without EPOCHSECONDS (before 5.0) keeps the find shape.
USE_CACHE=false
if [[ -s "$CACHE_FILE" ]]; then
  FRESH_REF="$CACHE_DIR/.fresh-24h"
  if [[ -n "${EPOCHSECONDS:-}" ]] &&
    printf -v FRESH_STAMP '%(%Y%m%d%H%M.%S)T' "$((EPOCHSECONDS - CFV_CACHE_WINDOW_MIN * 60))" 2>/dev/null &&
    touch -t "$FRESH_STAMP" "$FRESH_REF" 2>/dev/null; then
    [[ "$CACHE_FILE" -nt "$FRESH_REF" ]] && USE_CACHE=true
  elif find "$CACHE_FILE" -mmin "-$CFV_CACHE_WINDOW_MIN" 2>/dev/null | grep -q .; then
    USE_CACHE=true
  fi
fi

HELP_OUTPUT=""
if $USE_CACHE; then
  HELP_OUTPUT=$(<"$CACHE_FILE")
else
  # Run `<bin> [<subcmds>...] --help` with timeout 5s. 2>&1 catches binaries
  # that print --help to stderr (e.g. some legacy tools).
  if command -v timeout >/dev/null 2>&1; then
    HELP_OUTPUT=$(timeout 5 "$BIN" "${SUBCMDS[@]}" --help 2>&1)
    HELP_RC=$?
  else
    HELP_OUTPUT=$("$BIN" "${SUBCMDS[@]}" --help 2>&1)
    HELP_RC=$?
  fi
  # Some CLIs return non-zero on --help (e.g. busybox tools, malformed args).
  # Tolerate non-zero as long as output is non-empty and it did not time out.
  if [[ -z "$HELP_OUTPUT" ]] || ((HELP_RC == 124)); then
    $QUIET || echo "verify-cli-flag: '$BIN ${SUBCMDS[*]} --help' failed (rc=$HELP_RC, empty/timeout)" >&2
    exit 2
  fi
  # Persist to cache (best-effort).
  printf '%s' "$HELP_OUTPUT" >"$CACHE_FILE" 2>/dev/null || true
fi

# The match pattern is the shared definition (cli-flag-cache.sh documents the
# help-text shapes it accepts); the hook applies the same one on a cache hit.
FLAG_PATTERN=""
cfv_flag_pattern_to FLAG_PATTERN "$FLAG_NAME"
# Matched in-process: bash's `=~` is the same ERE dialect grep -E reads, and
# over the whole multi-line string the leading class admits the newline that
# precedes a line start, so a flag at the start of any --help line matches
# exactly as it did under grep. No pipe, no process, no pipe-capacity window.
# The --verbose path below still greps, because it wants the line number.
if [[ "$HELP_OUTPUT" =~ $FLAG_PATTERN ]]; then
  if $VERBOSE; then
    printf '%s\n' "$HELP_OUTPUT" | grep -nE "$FLAG_PATTERN" | head -1
  fi
  exit 0
fi

$QUIET || echo "verify-cli-flag: '$FLAG_NAME' not found in '$BIN ${SUBCMDS[*]} --help' output" >&2
exit 1
