#!/usr/bin/env bash
# portability-scope: fetches GitHub Actions logs through the GitHub REST API with gh; the script is the GitHub provider's log fetch.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_ID=""
JOB_ID=""
CHECKOUT=""
MAX_BYTES=52428800
KEEP_ZIP=0
RAW=0
ERRORS_ONLY=0
NOTICES=0
SHOW_GROUPS=0
TIMING=0
SUSPICIOUS=0

usage() {
  cat <<'EOF'
fetch-failed-logs.sh: fetch complete GitHub Actions logs for a workflow run and grep them.

Usage:
  fetch-failed-logs.sh <run-id> [options]
  fetch-failed-logs.sh --job <job-id>

  --job <id>       one job's plain-text log
  --errors-only    ##[error] only (default: ##[error] and ##[warning])
  --notices        also ##[notice]
  --groups         ##[group]/##[endgroup] step structure
  --timing         per-group durations
  --suspicious     retry, deprecation, zero-test and timeout patterns
  --audit          warnings, groups, timing and suspicious together
  --keep-zip       keep the ZIP in the scratch directory
  --raw            print the whole ZIP's contents, no grep
  --max-bytes <n>  size cap (default 52428800)
  --dir <checkout> any checkout of the run's repository (default: the current directory)
  FETCH_LOGS_REPO=owner/name wins over --dir; FETCH_LOGS_SCRATCH sets the ZIP directory.

Exit codes:
  0  log fetch + extraction succeeded
  1  invalid argument, or --dir names no directory
  2  gh api call failed (auth, network, 404 etc.)
  3  log payload exceeded the size cap
  4  ZIP extraction failed
  5  prerequisite missing (gh, unzip)
EOF
  exit 0
}

die() {
  printf 'fetch-failed-logs: %s\n' "$2" >&2
  exit "$1"
}

while (($# > 0)); do
  case "$1" in
  -h | --help) usage ;;
  --job)
    (($# >= 2)) || die 1 "--job needs an argument"
    JOB_ID="$2"
    shift
    ;;
  --max-bytes)
    [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die 1 "--max-bytes needs a numeric argument"
    MAX_BYTES="$2"
    shift
    ;;
  --dir)
    (($# >= 2)) && [[ -n "$2" && -z "$CHECKOUT" ]] || die 1 "--dir needs one value and is given once"
    CHECKOUT="$2"
    shift
    ;;
  --keep-zip) KEEP_ZIP=1 ;;
  --raw) RAW=1 ;;
  --errors-only) ERRORS_ONLY=1 ;;
  --notices) NOTICES=1 ;;
  --groups) SHOW_GROUPS=1 ;;
  --timing) TIMING=1 ;;
  --suspicious) SUSPICIOUS=1 ;;
  --audit) SHOW_GROUPS=1 TIMING=1 SUSPICIOUS=1 ;;
  --) break ;;
  -*) die 1 "unknown flag $(printf '%q' "$1") (use --help)" ;;
  *)
    [[ -z "$RUN_ID" ]] || die 1 "unexpected argument $(printf '%q' "$1")"
    RUN_ID="$1"
    ;;
  esac
  shift
done

MARKER_LEVELS=error
((ERRORS_ONLY)) || MARKER_LEVELS+="|warning"
((NOTICES)) && MARKER_LEVELS+="|notice"
MARKER_RE="##\[($MARKER_LEVELS)\]"

GROUP_MARKER_RE='##\[(group|endgroup)\]'

SUSPICIOUS_RE='(retry|retrying|attempt [0-9]+ of [0-9]+|exponential backoff|deprecat|0 tests|no tests (collected|run)|nothing to do|skipped due to|timed out|connection refused|fallback)' # spellchecker:disable-line

[[ -n "$RUN_ID" || -n "$JOB_ID" ]] || die 1 "<run-id> or --job <job-id> required"
[[ -z "$CHECKOUT" || -d "$CHECKOUT" ]] || die 1 "--dir $(printf '%q' "$CHECKOUT") is not a directory"

command -v gh >/dev/null 2>&1 || die 5 "gh CLI required"
command -v unzip >/dev/null 2>&1 || die 5 "unzip required"

file_size() { wc -c <"$1" | tr -d ' \r\n'; }

emit_group_timing() {
  local file="$1"
  awk '
    function ts_to_ms(ts,    parts, n, time, hh, mm, ss, frac, f) {
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

REPO="${FETCH_LOGS_REPO:-}"
if [[ -z "$REPO" && -n "$CHECKOUT" ]]; then
  REPO=$(bash "$SCRIPT_DIR/target-repo.sh" --dir "$CHECKOUT" | tr -d '\r\n')
elif [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null | tr -d '\r\n')
fi
[[ "$REPO" == */* ]] || die 2 "cannot resolve owner/repo (set FETCH_LOGS_REPO=owner/name)"

SCRATCH="${FETCH_LOGS_SCRATCH:-}"
scratch_owned=0
if [[ -z "$SCRATCH" ]]; then
  data_seg="${CLAUDE_PLUGIN_DATA:-}"
  data_seg="${data_seg%[/\\]}"
  data_seg="${data_seg##*[/\\]}"
  if [[ "$data_seg" == source-control || "$data_seg" == source-control-* ]]; then
    SCRATCH="$CLAUDE_PLUGIN_DATA/scratch"
  else
    SCRATCH=$(mktemp -d)
    scratch_owned=1
  fi
fi
mkdir -p "$SCRATCH"

EXTRACT_DIR=""
# shellcheck disable=SC2329  # invoked via trap, not direct call
cleanup() {
  local rc=$?
  [[ -z "$EXTRACT_DIR" ]] || rm -rf "$EXTRACT_DIR"
  if ((scratch_owned && KEEP_ZIP == 0 && rc != 3 && rc != 4)); then
    rm -rf "$SCRATCH"
  fi
}
trap cleanup EXIT

if [[ -n "$JOB_ID" ]]; then
  out_path="$SCRATCH/job-${JOB_ID}-logs.txt"
  if ! gh api "repos/$REPO/actions/jobs/$JOB_ID/logs" >"$out_path" 2>/dev/null; then
    printf 'fetch-failed-logs: gh api failed for job %s\n' "$JOB_ID" >&2
    rm -f "$out_path"
    exit 2
  fi
  size=$(file_size "$out_path")
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
      grep -E "$GROUP_MARKER_RE" "$out_path" || true
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

ZIP_PATH="$SCRATCH/run-${RUN_ID}-logs.zip"

if ! gh api "repos/$REPO/actions/runs/$RUN_ID/logs" >"$ZIP_PATH" 2>/dev/null; then
  printf 'fetch-failed-logs: gh api failed for run %s\n' "$RUN_ID" >&2
  rm -f "$ZIP_PATH"
  exit 2
fi

size=$(file_size "$ZIP_PATH")
if [[ "$size" -gt "$MAX_BYTES" ]]; then
  printf 'fetch-failed-logs: run log ZIP %s bytes > max %s — file kept at %s, not extracted\n' \
    "$size" "$MAX_BYTES" "$ZIP_PATH" >&2
  exit 3
fi

if [[ "$size" -lt 22 ]]; then
  printf 'fetch-failed-logs: response %s bytes — likely an API error, not a ZIP\n' "$size" >&2
  printf '  raw response: %s\n' "$(head -c 200 "$ZIP_PATH" || true)" >&2
  rm -f "$ZIP_PATH"
  exit 2
fi

EXTRACT_DIR=$(mktemp -d)

unzip -q "$ZIP_PATH" -d "$EXTRACT_DIR" 2>/dev/null || die 4 "unzip failed (corrupt ZIP at $ZIP_PATH)"

TXT_FILES=()
while IFS= read -r -d '' f; do
  TXT_FILES+=("$f")
done < <(find "$EXTRACT_DIR" -type f -name '*.txt' -print0 | sort -z)

per_file_section() {
  local banner="$1" f rel out
  shift
  printf '\n===== %s =====\n' "$banner"
  for f in ${TXT_FILES[@]+"${TXT_FILES[@]}"}; do
    rel="${f#"$EXTRACT_DIR"/}"
    out=$("$@" "$f") || true
    [[ -n "$out" ]] && printf '\n--- %s ---\n%s\n' "$rel" "$out"
  done
  return 0
}

# shellcheck disable=SC2329  # invoked as a per_file_section extractor
grep_group_markers() { grep -E "$GROUP_MARKER_RE" "$1" 2>/dev/null; }
# shellcheck disable=SC2329  # invoked as a per_file_section extractor
grep_suspicious() { grep -iE "$SUSPICIOUS_RE" "$1" 2>/dev/null; }

if [[ "$RAW" -eq 1 ]]; then
  for f in ${TXT_FILES[@]+"${TXT_FILES[@]}"}; do
    rel="${f#"$EXTRACT_DIR"/}"
    printf '\n===== %s =====\n' "$rel"
    cat "$f"
  done
else
  found_any=0
  for f in ${TXT_FILES[@]+"${TXT_FILES[@]}"}; do
    rel="${f#"$EXTRACT_DIR"/}"
    matches=$(grep -E "$MARKER_RE" "$f" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
      printf '\n===== %s =====\n%s\n' "$rel" "$matches"
      found_any=1
    fi
  done

  [[ "$SHOW_GROUPS" -eq 1 ]] && per_file_section "groups (step structure)" grep_group_markers
  [[ "$TIMING" -eq 1 ]] && per_file_section "timing (per group, ms)" emit_group_timing
  [[ "$SUSPICIOUS" -eq 1 ]] && per_file_section "suspicious patterns" grep_suspicious

  if [[ "$found_any" -eq 0 ]]; then
    largest=""
    largest_size=0
    for f in ${TXT_FILES[@]+"${TXT_FILES[@]}"}; do
      [[ "${f##*/}" == "system.txt" ]] && continue
      size=$(file_size "$f" 2>/dev/null)
      [[ -z "$size" ]] && continue
      if [[ "$size" -gt "$largest_size" ]]; then
        largest="$f"
        largest_size="$size"
      fi
    done

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
