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

# Cache directory — derived constants (fixed by env, not flags).
if [[ -n "${LOCALAPPDATA:-}" ]]; then
  CACHE_BASE="${LOCALAPPDATA//\\//}/guardrails"
else
  CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/guardrails"
fi
CACHE_DIR="$CACHE_BASE/cli-flag-cache"
mkdir -p "$CACHE_DIR" 2>/dev/null || true

# Cache key: bin + subcmds joined by '__'. Slugify path-unsafe chars to '_'.
CACHE_KEY="$BIN"
for s in "${SUBCMDS[@]}"; do
  CACHE_KEY="${CACHE_KEY}__${s}"
done
CACHE_KEY="${CACHE_KEY//[^a-zA-Z0-9_-]/_}"
CACHE_FILE="$CACHE_DIR/$CACHE_KEY.help"

# Cache hit if file exists, mtime within 24h, non-empty.
USE_CACHE=false
if [[ -s "$CACHE_FILE" ]]; then
  if find "$CACHE_FILE" -mmin -1440 2>/dev/null | grep -q .; then
    USE_CACHE=true
  fi
fi

HELP_OUTPUT=""
if $USE_CACHE; then
  HELP_OUTPUT=$(cat "$CACHE_FILE")
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
  # Tolerate non-zero IF output is non-empty AND looks like help text.
  if [[ -z "$HELP_OUTPUT" ]] || ((HELP_RC == 124)); then
    $QUIET || echo "verify-cli-flag: '$BIN ${SUBCMDS[*]} --help' failed (rc=$HELP_RC, empty/timeout)" >&2
    exit 2
  fi
  # Persist to cache (best-effort).
  printf '%s' "$HELP_OUTPUT" >"$CACHE_FILE" 2>/dev/null || true
fi

# Match anchored on word boundaries. The flag may appear as:
#   `  --flag         description`            (column-aligned)
#   `  --flag <ARG>   description`            (with metavar)
#   `  --flag=VALUE`                          (equals form)
#   `  -F, --flag`                            (with short form)
#   `  --flag, -F`                            (reverse short form)
#   `  [--flag]`                              (optional-arg notation)
#   `  [-S|--save|--save-dev|--save-optional]` (pipe-separated synopsis, e.g. npm)
#   `--flag` inside a usage line               (rare but valid)
# Pattern: `--flag` followed by a flag terminator — space, =, comma, `[`, `]`,
# `|`, `)`, or end-of-line. The trailing class lists `]` first (literal), then
# the POSIX space class and the remaining literals. The leading
# `(^|[^a-zA-Z0-9_-])` plus this trailing terminator prevent a prefix false
# match (e.g. searching `--save-dev` must not match `--save-developer`).
FLAG_PATTERN="(^|[^a-zA-Z0-9_-])${FLAG_NAME}([][:space:]=,|)[]|\$)"
if grep -E "$FLAG_PATTERN" <<<"$HELP_OUTPUT" >/dev/null; then
  if $VERBOSE; then
    grep -nE "$FLAG_PATTERN" <<<"$HELP_OUTPUT" | head -1
  fi
  exit 0
fi

$QUIET || echo "verify-cli-flag: '$FLAG_NAME' not found in '$BIN ${SUBCMDS[*]} --help' output" >&2
exit 1
