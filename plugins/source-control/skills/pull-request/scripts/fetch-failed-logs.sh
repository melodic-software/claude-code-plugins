#!/usr/bin/env bash
# fetch-failed-logs.sh — Fetch complete, untruncated GitHub Actions logs
# for a workflow run via the GitHub REST API.
#
# Replaces the truncation-prone `gh run view <id> --log-failed` (CLI display
# layer caps at ~4MB; cli/cli #11059 #10551 #7771 #7642). Uses direct
# `gh api .../runs/{id}/logs` (full ZIP via Azure Blob 302) or
# `gh api .../jobs/{id}/logs` (per-job plain text) — both complete.
#
# Default mode greps `##[error]` and `##[warning]` per file. Audit flags
# expose more observability surface for a CI-log-audit agent (if your
# environment ships one) and for ad-hoc inline use.
#
# Usage:
#   fetch-failed-logs.sh <run-id>                  # default: ##[error] + ##[warning]
#   fetch-failed-logs.sh --job <job-id>            # single-job plain-text mode
#   fetch-failed-logs.sh <run-id> --errors-only    # ##[error] only (no warnings)
#   fetch-failed-logs.sh <run-id> --notices        # also include ##[notice]
#   fetch-failed-logs.sh <run-id> --groups         # ##[group]/##[endgroup] step structure
#   fetch-failed-logs.sh <run-id> --timing         # per-group durations from ISO timestamps
#   fetch-failed-logs.sh <run-id> --suspicious     # grep retry/deprecation/0-tests/timeout patterns
#   fetch-failed-logs.sh <run-id> --audit          # macro: warnings + groups + timing + suspicious
#   fetch-failed-logs.sh <run-id> --keep-zip       # leave ZIP under scratch/ for re-grep
#   fetch-failed-logs.sh <run-id> --raw            # dump full ZIP contents to stdout (no grep)
#   fetch-failed-logs.sh <run-id> --max-bytes <n>  # size cap (default 52428800 = 50 MiB) — the
#                                                  # invoking skill wires the fetch_logs_max_bytes
#                                                  # userConfig option here
#
# Env overrides:
#   FETCH_LOGS_REPO        default `gh repo view --json nameWithOwner -q .nameWithOwner`
#   FETCH_LOGS_SCRATCH     destination for cached ZIPs — default
#                          $CLAUDE_PLUGIN_DATA/scratch when set, else mktemp -d
#
# Exit codes:
#   0  log fetch + extraction succeeded
#   1  invalid argument
#   2  gh api call failed (auth, network, 404 etc.)
#   3  log payload exceeded the size cap
#   4  ZIP extraction failed
#   5  prerequisite missing (gh, unzip)

set -uo pipefail

# --- Argument parsing --------------------------------------------------------

RUN_ID=""
JOB_ID=""
MAX_BYTES_ARG=""
KEEP_ZIP=0
RAW=0
ERRORS_ONLY=0
NOTICES=0
SHOW_GROUPS=0
TIMING=0
SUSPICIOUS=0

usage() {
  sed -n '2,41p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --job)
    [[ $# -ge 2 ]] || {
      printf 'fetch-failed-logs: --job needs an argument\n' >&2
      exit 1
    }
    JOB_ID="$2"
    shift 2
    ;;
  --max-bytes)
    [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || {
      printf 'fetch-failed-logs: --max-bytes needs a numeric argument\n' >&2
      exit 1
    }
    MAX_BYTES_ARG="$2"
    shift 2
    ;;
  --keep-zip)
    KEEP_ZIP=1
    shift
    ;;
  --raw)
    RAW=1
    shift
    ;;
  --errors-only)
    ERRORS_ONLY=1
    shift
    ;;
  --notices)
    NOTICES=1
    shift
    ;;
  --groups)
    SHOW_GROUPS=1
    shift
    ;;
  --timing)
    TIMING=1
    shift
    ;;
  --suspicious)
    SUSPICIOUS=1
    shift
    ;;
  --audit)
    # Macro: comprehensive observability beyond default error+warning grep.
    SHOW_GROUPS=1
    TIMING=1
    SUSPICIOUS=1
    shift
    ;;
  --)
    shift
    break
    ;;
  -*)
    printf 'fetch-failed-logs: unknown flag %q (use --help)\n' "$1" >&2
    exit 1
    ;;
  *)
    if [[ -z "$RUN_ID" ]]; then
      RUN_ID="$1"
    else
      printf 'fetch-failed-logs: unexpected argument %q\n' "$1" >&2
      exit 1
    fi
    shift
    ;;
  esac
done

# Compose marker regex based on flags. ERRORS_ONLY suppresses warning;
# NOTICES adds notice. Default = error + warning (preserving v1 behavior).
if [[ "$ERRORS_ONLY" -eq 1 && "$NOTICES" -eq 1 ]]; then
  MARKER_RE='##\[(error|notice)\]'
elif [[ "$ERRORS_ONLY" -eq 1 ]]; then
  MARKER_RE='##\[error\]'
elif [[ "$NOTICES" -eq 1 ]]; then
  MARKER_RE='##\[(error|warning|notice)\]'
else
  MARKER_RE='##\[(error|warning)\]'
fi

# Suspicious-pattern regex — case-insensitive grep targets commonly-missed
# signal: retry loops, deprecation warnings, "0 tests" lies, timeouts,
# exit-code mismatches not flagged as ##[error].
SUSPICIOUS_RE='(retry|retrying|attempt [0-9]+ of [0-9]+|exponential backoff|deprecat|0 tests|no tests (collected|run)|nothing to do|skipped due to|timed out|connection refused|fallback)' # spellchecker:disable-line

if [[ -z "$RUN_ID" && -z "$JOB_ID" ]]; then
  printf 'fetch-failed-logs: <run-id> or --job <job-id> required\n' >&2
  exit 1
fi

# --- Prerequisites -----------------------------------------------------------

have() { command -v "$1" >/dev/null 2>&1; }

# emit_group_timing — parse leading ISO 8601 timestamp on each line, compute
# duration per ##[group]/##[endgroup] section. Pure awk for cross-platform.
# GH Actions logs prefix every line with `2026-MM-DDThh:mm:ss.NZ ` followed
# by the message. We diff first/last timestamp inside each group block.
emit_group_timing() {
  local file="$1"
  awk '
    function ts_to_ms(ts,    s, ms, parts) {
      # Parse 2026-05-07T15:24:44.3187916Z → epoch_ms (approximate using only
      # hh:mm:ss.fff for relative duration; date arithmetic stays inside the
      # same UTC day for typical CI runs).
      if (ts !~ /T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) return 0
      n = split(ts, parts, "T")
      if (n < 2) return 0
      time = parts[2]
      hh = substr(time, 1, 2) + 0
      mm = substr(time, 4, 2) + 0
      ss = substr(time, 7, 2) + 0
      frac = 0
      if (substr(time, 9, 1) == ".") {
        # take up to 3 decimal digits for ms
        f = substr(time, 10, 3)
        gsub(/[^0-9]/, "", f)
        if (length(f) > 0) frac = f + 0
      }
      return ((hh * 3600 + mm * 60 + ss) * 1000) + frac
    }
    {
      # Capture timestamp prefix
      if (match($0, /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+Z/)) {
        ts = substr($0, 1, RLENGTH)
        msg = substr($0, RLENGTH + 2)
      } else {
        next
      }
      if (match(msg, /##\[group\]/)) {
        gname = substr(msg, RSTART + RLENGTH)
        gstart = ts_to_ms(ts)
        in_group = 1
        next
      }
      if (in_group && match(msg, /##\[endgroup\]/)) {
        gend = ts_to_ms(ts)
        dur = gend - gstart
        if (dur < 0) dur = dur + 86400000  # crossed UTC midnight
        printf "%6d ms  %s\n", dur, gname
        in_group = 0
      }
    }
  ' "$file"
}

have gh || {
  printf 'fetch-failed-logs: gh CLI required\n' >&2
  exit 5
}
have unzip || {
  printf 'fetch-failed-logs: unzip required\n' >&2
  exit 5
}

MAX_BYTES="${MAX_BYTES_ARG:-52428800}"

# --- Repo resolution ---------------------------------------------------------

if [[ -n "${FETCH_LOGS_REPO:-}" ]]; then
  REPO="$FETCH_LOGS_REPO"
else
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null | tr -d '\r\n')
fi

if [[ -z "$REPO" || "$REPO" != */* ]]; then
  printf 'fetch-failed-logs: cannot resolve owner/repo (set FETCH_LOGS_REPO=owner/name)\n' >&2
  exit 2
fi

# --- Scratch dir resolution --------------------------------------------------
#
# Cached ZIPs and extracted logs are transient. Precedence: explicit
# FETCH_LOGS_SCRATCH override > the plugin's persistent data directory
# (CLAUDE_PLUGIN_DATA, set when running as an installed plugin) > mktemp.

SCRATCH="${FETCH_LOGS_SCRATCH:-}"
if [[ -z "$SCRATCH" ]]; then
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    SCRATCH="$CLAUDE_PLUGIN_DATA/scratch"
  else
    SCRATCH=$(mktemp -d)
  fi
fi
mkdir -p "$SCRATCH"

# --- Per-job mode ------------------------------------------------------------

if [[ -n "$JOB_ID" ]]; then
  out_path="$SCRATCH/job-${JOB_ID}-logs.txt"
  if ! gh api "repos/$REPO/actions/jobs/$JOB_ID/logs" >"$out_path" 2>/dev/null; then
    printf 'fetch-failed-logs: gh api failed for job %s\n' "$JOB_ID" >&2
    rm -f "$out_path"
    exit 2
  fi
  size=$(wc -c <"$out_path" | tr -d ' \r\n')
  if [[ "$size" -gt "$MAX_BYTES" ]]; then
    printf 'fetch-failed-logs: job log %s bytes > max %s — wrote to %s, not printing\n' \
      "$size" "$MAX_BYTES" "$out_path" >&2
    exit 3
  fi
  if [[ "$RAW" -eq 1 ]]; then
    cat "$out_path"
  else
    grep -E "$MARKER_RE" "$out_path" || true
    if [[ "$SHOW_GROUPS" -eq 1 ]]; then
      printf '\n----- groups -----\n'
      grep -E '##\[(group|endgroup)\]' "$out_path" || true
    fi
    if [[ "$TIMING" -eq 1 ]]; then
      printf '\n----- timing (per group) -----\n'
      emit_group_timing "$out_path"
    fi
    if [[ "$SUSPICIOUS" -eq 1 ]]; then
      printf '\n----- suspicious patterns -----\n'
      grep -iE "$SUSPICIOUS_RE" "$out_path" || true
    fi
  fi
  exit 0
fi

# --- Full-run ZIP mode -------------------------------------------------------

ZIP_PATH="$SCRATCH/run-${RUN_ID}-logs.zip"

if ! gh api "repos/$REPO/actions/runs/$RUN_ID/logs" >"$ZIP_PATH" 2>/dev/null; then
  printf 'fetch-failed-logs: gh api failed for run %s\n' "$RUN_ID" >&2
  rm -f "$ZIP_PATH"
  exit 2
fi

size=$(wc -c <"$ZIP_PATH" | tr -d ' \r\n')
if [[ "$size" -gt "$MAX_BYTES" ]]; then
  printf 'fetch-failed-logs: run log ZIP %s bytes > max %s — file kept at %s, not extracted\n' \
    "$size" "$MAX_BYTES" "$ZIP_PATH" >&2
  exit 3
fi

if [[ "$size" -lt 22 ]]; then
  # ZIP minimum is 22 bytes (empty central directory). Anything smaller is an
  # API error response that gh somehow piped through.
  printf 'fetch-failed-logs: response %s bytes — likely an API error, not a ZIP\n' "$size" >&2
  printf '  raw response: %s\n' "$(head -c 200 "$ZIP_PATH" || true)" >&2
  rm -f "$ZIP_PATH"
  exit 2
fi

# Extract to a temporary directory and walk per-job folders.
EXTRACT_DIR=$(mktemp -d)
# shellcheck disable=SC2329  # invoked via trap, not direct call
cleanup_extract() { rm -rf "$EXTRACT_DIR"; }
trap cleanup_extract EXIT INT TERM

if ! unzip -q "$ZIP_PATH" -d "$EXTRACT_DIR" 2>/dev/null; then
  printf 'fetch-failed-logs: unzip failed (corrupt ZIP at %s)\n' "$ZIP_PATH" >&2
  exit 4
fi

# Real GitHub Actions ZIP layout (verified 2026-05-08 against run 25505236665):
#   TOP-LEVEL:  <step-num>_<job-name>.txt    consolidated step log (errors live here)
#   PER-JOB:    <job-name>/system.txt         agent metadata only
# Errors appear in the top-level consolidated files. Walk all *.txt recursively
# rather than per-job dirs (the prior fixture-only logic missed real layouts).

if [[ "$RAW" -eq 1 ]]; then
  # Dump every text file with a header for orientation. NUL-delimited to
  # survive filenames with spaces (real ZIPs have them — e.g. "shell _ Bash").
  while IFS= read -r -d '' f; do
    rel="${f#"$EXTRACT_DIR"/}"
    printf '\n===== %s =====\n' "$rel"
    cat "$f"
  done < <(find "$EXTRACT_DIR" -type f -name '*.txt' -print0 | sort -z)
else
  # Walk every .txt file recursively, grep for markers, group output by file.
  found_any=0
  while IFS= read -r -d '' f; do
    rel="${f#"$EXTRACT_DIR"/}"
    matches=$(grep -E "$MARKER_RE" "$f" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      printf '\n===== %s =====\n%s\n' "$rel" "$matches"
      found_any=1
    fi
  done < <(find "$EXTRACT_DIR" -type f -name '*.txt' -print0 | sort -z)

  # --- Audit-flag sections (when requested) ---
  if [[ "$SHOW_GROUPS" -eq 1 ]]; then
    printf '\n===== groups (step structure) =====\n'
    while IFS= read -r -d '' f; do
      rel="${f#"$EXTRACT_DIR"/}"
      g=$(grep -E '##\[(group|endgroup)\]' "$f" 2>/dev/null || true)
      [[ -n "$g" ]] && printf '\n--- %s ---\n%s\n' "$rel" "$g"
    done < <(find "$EXTRACT_DIR" -type f -name '*.txt' -print0 | sort -z)
  fi

  if [[ "$TIMING" -eq 1 ]]; then
    printf '\n===== timing (per group, ms) =====\n'
    while IFS= read -r -d '' f; do
      rel="${f#"$EXTRACT_DIR"/}"
      timing=$(emit_group_timing "$f")
      [[ -n "$timing" ]] && printf '\n--- %s ---\n%s\n' "$rel" "$timing"
    done < <(find "$EXTRACT_DIR" -type f -name '*.txt' -print0 | sort -z)
  fi

  if [[ "$SUSPICIOUS" -eq 1 ]]; then
    printf '\n===== suspicious patterns =====\n'
    while IFS= read -r -d '' f; do
      rel="${f#"$EXTRACT_DIR"/}"
      sus=$(grep -iE "$SUSPICIOUS_RE" "$f" 2>/dev/null || true)
      [[ -n "$sus" ]] && printf '\n--- %s ---\n%s\n' "$rel" "$sus"
    done < <(find "$EXTRACT_DIR" -type f -name '*.txt' -print0 | sort -z)
  fi

  if [[ "$found_any" -eq 0 ]]; then
    # No marker found — surface tail of the largest non-system log file. Use
    # `wc -c` for cross-platform portability (find -printf is GNU-only; macOS
    # BSD find rejects it).
    largest=""
    largest_size=0
    while IFS= read -r -d '' f; do
      [[ "$(basename "$f")" == "system.txt" ]] && continue
      size=$(wc -c <"$f" 2>/dev/null | tr -d ' \r\n')
      [[ -z "$size" ]] && continue
      if [[ "$size" -gt "$largest_size" ]]; then
        largest="$f"
        largest_size="$size"
      fi
    done < <(find "$EXTRACT_DIR" -type f -name '*.txt' -print0)

    if [[ -n "$largest" ]]; then
      printf 'fetch-failed-logs: no ##[error]/##[warning] markers found. Tail of %s:\n' \
        "${largest#"$EXTRACT_DIR"/}" >&2
      tail -30 "$largest" >&2
    else
      printf 'fetch-failed-logs: ZIP extracted but no .txt files found\n' >&2
    fi
  fi
fi

if [[ "$KEEP_ZIP" -eq 0 ]]; then
  rm -f "$ZIP_PATH"
fi

exit 0
