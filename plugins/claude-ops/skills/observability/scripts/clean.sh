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
#   3. skill-usage.jsonl — OPT-IN, and inert unless --skill-usage-scope is passed. Its own
#      far longer window (--keep-skill-usage-days, default 365): it feeds a starvation report
#      that wants long history, and its rows carry skill names and branches only, no content.
#      Scope and dir are FLAGS, never environment: a skill-spawned subprocess inherits no
#      CLAUDE_PLUGIN_OPTION_*, and CLAUDE_PLUGIN_DATA there was observed pointing at an
#      unrelated plugin's data directory — so `data-dir` demands an explicit --skill-usage-dir.
#
# Usage:
#   bash clean.sh [--keep-days N] [--dry-run] [--quiet]
#                 [--skill-usage-scope repo|user|data-dir] [--skill-usage-dir REL]
#                 [--keep-skill-usage-days N]
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
# Skill-usage pruning is INERT unless --skill-usage-scope is passed. That is the
# rollback story: with the flag absent this script's behavior is byte-for-byte
# what it was, so reverting the feature is dropping one branch.
SKILL_USAGE_SCOPE=""
SKILL_USAGE_DIR=".claude/observability"
# Only used by the data-dir scope, and only ever supplied explicitly.
SKILL_USAGE_DATA_ROOT=""
# Its own window, deliberately far longer than the 30-day hook-events default:
# the store is the input to a starvation report that WANTS long history, and its
# rows carry names and branches only, not content.
KEEP_SKILL_USAGE_DAYS=365

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
  --skill-usage-scope)
    shift
    SKILL_USAGE_SCOPE="${1:-}"
    shift
    ;;
  --skill-usage-scope=*)
    SKILL_USAGE_SCOPE="${1#*=}"
    shift
    ;;
  --skill-usage-dir)
    shift
    SKILL_USAGE_DIR="${1:-}"
    shift
    ;;
  --skill-usage-dir=*)
    SKILL_USAGE_DIR="${1#*=}"
    shift
    ;;
  --skill-usage-data-root)
    shift
    SKILL_USAGE_DATA_ROOT="${1:-}"
    shift
    ;;
  --skill-usage-data-root=*)
    SKILL_USAGE_DATA_ROOT="${1#*=}"
    shift
    ;;
  --keep-skill-usage-days)
    shift
    KEEP_SKILL_USAGE_DAYS="${1:-365}"
    shift
    ;;
  --keep-skill-usage-days=*)
    KEEP_SKILL_USAGE_DAYS="${1#*=}"
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
    echo "Usage: $0 [--keep-days N] [--dry-run] [--quiet] [--skill-usage-scope repo|user|data-dir] [--skill-usage-dir REL] [--keep-skill-usage-days N]" >&2
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
  CUTOFF_EPOCH=$(date -u -d "${KEEP_DAYS} days ago" +%s)        # portability-ok: see if-guard above (#1510)
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
  # Third arg is an optional per-target cutoff. Absent, the caller's global
  # window applies -- so the hook-events call site is byte-for-byte unchanged.
  local CUTOFF_ISO="${3:-$CUTOFF_ISO}"
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

# Resolved once, above every consumer: the skill-usage data-dir branch below and
# the OTEL delegation further down both need it.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

prune_file "$HOOK_LOG" "ts"

# --- skill-usage.jsonl (opt-in, its own window, its own resolved location) ---
# Inert unless --skill-usage-scope is passed, so the default run is unchanged.
#
# The scope and dir arrive as FLAGS rather than being read from the environment.
# This script runs as a skill-spawned subprocess, which does not inherit
# CLAUDE_PLUGIN_OPTION_* -- so it cannot see the hook's configured scope -- and
# CLAUDE_PLUGIN_DATA in that context was observed pointing at an UNRELATED
# plugin's data directory. Deriving a delete path from either would risk pruning
# somebody else's files, which is why `data-dir` demands an explicit directory
# and is never guessed.
if [[ -n "$SKILL_USAGE_SCOPE" ]]; then
  case "$KEEP_SKILL_USAGE_DAYS" in
  *[!0-9]*)
    echo "ERROR: --keep-skill-usage-days must be a non-negative integer (got: $KEEP_SKILL_USAGE_DAYS)" >&2
    exit 2
    ;;
  *) ;;
  esac

  case "$SKILL_USAGE_DIR" in
  /* | [A-Za-z]:* | *..*)
    echo "ERROR: --skill-usage-dir must be a contained relative path (got: $SKILL_USAGE_DIR)" >&2
    exit 2
    ;;
  # A contained relative path is the only accepted shape; anything absolute,
  # drive-qualified, or traversing was rejected above.
  *) ;;
  esac

  SKILL_USAGE_BASE=""
  case "$SKILL_USAGE_SCOPE" in
  repo) SKILL_USAGE_BASE="$REPO_ROOT" ;;
  user) SKILL_USAGE_BASE="${HOME:-}" ;;
  data-dir)
    # The writer stores rows at ${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>,
    # NOT at a repo-relative path — so this branch must reproduce that layout or
    # it prunes a file the writer never touches. The data root is still never
    # taken from the environment (a skill subprocess saw it pointing at an
    # unrelated plugin's directory); it is supplied explicitly and the slug is
    # re-derived here with the writer's own algorithm.
    if [[ -z "$SKILL_USAGE_DATA_ROOT" ]]; then
      echo "ERROR: --skill-usage-scope data-dir requires --skill-usage-data-root <path>" >&2
      echo "       (the plugin data root; CLAUDE_PLUGIN_DATA is not dependable here)" >&2
      exit 2
    fi
    case "$SKILL_USAGE_DATA_ROOT" in
    /* | [A-Za-z]:*) ;;
    *)
      echo "ERROR: --skill-usage-data-root must be an absolute path (got: $SKILL_USAGE_DATA_ROOT)" >&2
      exit 2
      ;;
    esac
    ;;
  *)
    echo "ERROR: --skill-usage-scope must be repo, user, or data-dir (got: $SKILL_USAGE_SCOPE)" >&2
    exit 2
    ;;
  esac

  # data-dir builds its path from the supplied data root, not from a base.
  if [[ "$SKILL_USAGE_SCOPE" != "data-dir" && -z "$SKILL_USAGE_BASE" ]]; then
    echo "ERROR: could not resolve a base directory for scope $SKILL_USAGE_SCOPE" >&2
    exit 2
  fi

  # portability-ok: GNU-first dual-dialect probe, BSD branch in the else below (#1510)
  if date -u -d "1 day ago" +%s >/dev/null 2>&1; then
    SU_EPOCH=$(date -u -d "${KEEP_SKILL_USAGE_DAYS} days ago" +%s) # portability-ok: see if-guard above (#1510)
    SU_CUTOFF_ISO=$(date -u -d "@$SU_EPOCH" +%Y-%m-%dT%H:%M:%SZ)   # portability-ok: see if-guard above (#1510)
  else
    SU_EPOCH=$(date -u -v-"${KEEP_SKILL_USAGE_DAYS}"d +%s)
    SU_CUTOFF_ISO=$(date -u -r "$SU_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
  fi

  if [[ "$SKILL_USAGE_SCOPE" == "data-dir" ]]; then
    # Reproduce the writer's layout: <data-root>/skill-usage/<repo-slug>. The
    # slug algorithm lives with the hooks; source it rather than restating it,
    # so the two cannot drift into pruning different paths.
    # shellcheck source=../../../hooks/hook-utils.sh
    . "${SKILL_DIR}/../../hooks/hook-utils.sh"
    # shellcheck source=../../../hooks/claude-ops-paths.sh
    . "${SKILL_DIR}/../../hooks/claude-ops-paths.sh"
    SKILL_USAGE_LOG="${SKILL_USAGE_DATA_ROOT%/}/skill-usage/$(claude_ops::repo_slug "$REPO_ROOT")/skill-usage.jsonl"
  else
    SKILL_USAGE_LOG="${SKILL_USAGE_BASE%/}/${SKILL_USAGE_DIR}/skill-usage.jsonl"
  fi
  log "clean: skill-usage (scope $SKILL_USAGE_SCOPE, keeping on/after $SU_CUTOFF_ISO, --keep-skill-usage-days $KEEP_SKILL_USAGE_DAYS)"
  log "clean: skill-usage target $SKILL_USAGE_LOG"
  prune_file "$SKILL_USAGE_LOG" "ts" "$SU_CUTOFF_ISO"
fi

# --- OTEL file store (separate, tighter retention window; Collector-stop-coordinated) ---
# Delegated to the shared tool — the OTEL store needs Collector-stop coordination the JSONL
# prune does not. It uses its own CC_OTEL_RETENTION_DAYS / CC_OTEL_BODY_RETENTION_DAYS env
# windows (defaults 7 / 2), NOT --keep-days, and only stops the Collector when records
# actually exceed a window (it dry-checks first).
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
