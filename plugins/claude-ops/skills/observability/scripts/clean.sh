#!/usr/bin/env bash
# /observability clean — prune local observability data by age.
# Two layers, two retention windows:
#   1. JSONL metadata (.claude/observability/hook-events.jsonl) —
#      path-only, pruned in place to the --keep-days window (default 30).
#   2. OTEL file store (.claude/observability/otel/{cc-logs,cc-metrics}.json) — holds full
#      prompt + raw API bodies, so TIGHTER windows: CC_OTEL_RETENTION_DAYS (default 7) for
#      structure events, CC_OTEL_BODY_RETENTION_DAYS (default 2) for api_*_body records.
#      Delegated to otel/prune-otel-store.sh in this skill, which stops + restarts the
#      machine-singleton Collector around the trim (only when records actually exceed a window).
#
# Usage:
#   bash clean.sh [--keep-days N] [--dry-run] [--quiet]
#
# Flags:
#   --keep-days N   JSONL retention window in days (default: 30). The OTEL store uses its own
#                   CC_OTEL_RETENTION_DAYS / CC_OTEL_BODY_RETENTION_DAYS env windows
#                   (defaults 7 / 2), NOT this flag.
#   --dry-run       Report would-prune counts for BOTH layers; modify nothing
#   --quiet         Suppress progress output (still prints final summary)
#
# Behavior (JSONL layer):
#   - Atomic temp+rename per file (POSIX rename atomicity)
#   - flock with 5s timeout — on contention, skips the file and reports
#   - Exits 0 on success or skip-on-contention; non-zero only on jq/IO failure
#   - Reports before/after byte + line counts
#   - Empty/missing files: skipped silently
#
# Cross-platform: Git Bash on Windows, Linux, macOS (bash 5+).

# No -e: failures are checked explicitly via captured $? so a single file's
# jq/IO error skips that file rather than aborting the whole prune.
set -uo pipefail

KEEP_DAYS=30
DRY_RUN=0
QUIET=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-days)
      shift
      KEEP_DAYS="${1:-30}"
      shift
      ;;
    --keep-days=*)
      KEEP_DAYS="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --quiet)
      QUIET=1
      shift
      ;;
    -h | --help)
      sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unknown flag: $1" >&2
      echo "Usage: $0 [--keep-days N] [--dry-run] [--quiet]" >&2
      exit 2
      ;;
  esac
done

case "$KEEP_DAYS" in
  *[!0-9]*)
    echo "ERROR: --keep-days must be a non-negative integer (got: $KEEP_DAYS)" >&2
    exit 2
    ;;
  *) ;;
esac

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')}"
if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: not in a git repo (and CLAUDE_PROJECT_DIR is unset)" >&2
  exit 2
fi

OBS_DIR="${REPO_ROOT}/.claude/observability"
HOOK_LOG="${OBS_DIR}/hook-events.jsonl"

# Cutoff timestamp — ISO-8601 UTC. GNU date (Linux/Git Bash) and BSD date (macOS)
# require different flags for relative time and epoch-to-ISO conversion.
# portability-ok: GNU-first dual-dialect probe, BSD branch in the else below (#1510)
if date -u -d "1 day ago" +%s >/dev/null 2>&1; then
  CUTOFF_EPOCH=$(date -u -d "${KEEP_DAYS} days ago" +%s) # portability-ok: see if-guard above (#1510)
  CUTOFF_ISO=$(date -u -d "@$CUTOFF_EPOCH" +%Y-%m-%dT%H:%M:%SZ) # portability-ok: see if-guard above (#1510)
else
  # macOS BSD date
  CUTOFF_EPOCH=$(date -u -v-"${KEEP_DAYS}"d +%s)
  CUTOFF_ISO=$(date -u -r "$CUTOFF_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
fi

log() {
  if [[ "$QUIET" -eq 0 ]]; then echo "$@" >&2; fi
}

log "clean: keeping entries on/after $CUTOFF_ISO (--keep-days $KEEP_DAYS)"
[[ "$DRY_RUN" -eq 1 ]] && log "clean: DRY-RUN — no files will be modified"

# Process one file. Args: file_path, timestamp_field.
prune_file() {
  local file="$1" ts_field="$2"
  local label
  label=$(basename "$file")

  if [[ ! -f "$file" ]]; then
    log "  ${label}: missing — skip"
    return 0
  fi

  local before_lines before_bytes
  before_lines=$(wc -l <"$file" 2>/dev/null | tr -d ' \r')
  before_bytes=$(wc -c <"$file" 2>/dev/null | tr -d ' \r')

  if [[ "$before_lines" -eq 0 ]]; then
    log "  ${label}: empty — skip"
    return 0
  fi

  # Count what would survive
  local kept_count
  kept_count=$(jq -c --arg cutoff "$CUTOFF_ISO" --arg ts "$ts_field" \
    'select(.[$ts] >= $cutoff)' "$file" 2>/dev/null | wc -l | tr -d ' \r')

  local pruned=$((before_lines - kept_count))

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  %s: %d lines, %d bytes → would keep %d, prune %d\n' \
      "$label" "$before_lines" "$before_bytes" "$kept_count" "$pruned"
    return 0
  fi

  if [[ "$pruned" -eq 0 ]]; then
    log "  ${label}: ${before_lines} lines all within window — no change"
    return 0
  fi

  local tmp="${file}.tmp.$$"
  local lock="${file}.lock"

  # Only a fully clean jq pass may replace the file: on a malformed line jq
  # STOPS reading the stream, so $tmp holds only the records before the bad
  # line — promoting it would silently drop every valid event after it. A
  # file with a malformed line is therefore skipped intact (any nonzero rc).
  run_jq() {
    jq -c --arg cutoff "$CUTOFF_ISO" --arg ts "$ts_field" \
      'select(.[$ts] >= $cutoff)' "$file" >"$tmp" 2>/dev/null
  }

  local rc=0
  if command -v flock >/dev/null 2>&1; then
    (
      flock -x -w 5 9 || {
        echo "  ${label}: flock timeout — skip (active writer)" >&2
        exit 1
      }
      run_jq && mv -f "$tmp" "$file"
    ) 9>"$lock"
    rc=$?
  else
    if run_jq; then
      mv -f "$tmp" "$file" || rc=$?
    else
      rc=$?
      echo "  ${label}: jq failed — skip" >&2
    fi
  fi
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$tmp" 2>/dev/null
    return 0
  fi

  local after_lines after_bytes
  after_lines=$(wc -l <"$file" 2>/dev/null | tr -d ' \r')
  after_bytes=$(wc -c <"$file" 2>/dev/null | tr -d ' \r')

  printf '  %s: %d → %d lines (%d pruned); %d → %d bytes\n' \
    "$label" "$before_lines" "$after_lines" "$pruned" "$before_bytes" "$after_bytes"
}

prune_file "$HOOK_LOG" "ts"

# --- OTEL file store (separate, tighter retention window; Collector-stop-coordinated) ---
# Delegated to the shared tool — the OTEL store needs Collector-stop coordination the JSONL
# prune does not. It uses its own CC_OTEL_RETENTION_DAYS / CC_OTEL_BODY_RETENTION_DAYS env
# windows (defaults 7 / 2), NOT --keep-days, and only stops the Collector when records
# actually exceed a window (it dry-checks first).
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRUNE_OTEL="${SKILL_DIR}/otel/prune-otel-store.sh"
if [[ -f "$PRUNE_OTEL" ]]; then
  log "clean: OTEL store (CC_OTEL_RETENTION_DAYS=${CC_OTEL_RETENTION_DAYS:-7}, CC_OTEL_BODY_RETENTION_DAYS=${CC_OTEL_BODY_RETENTION_DAYS:-2}; stops Collector only if records exceed a window)"
  export CC_OTEL_STORE="${CC_OTEL_STORE:-$REPO_ROOT/.claude/observability/otel}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    bash "$PRUNE_OTEL" --dry-run || log "  prune-otel-store.sh: dry-run returned non-zero"
  else
    bash "$PRUNE_OTEL" || log "  prune-otel-store.sh: returned non-zero (OTEL store may be unchanged)"
  fi
else
  log "  prune-otel-store.sh: not found — skipping OTEL store"
fi

log "clean: done"
