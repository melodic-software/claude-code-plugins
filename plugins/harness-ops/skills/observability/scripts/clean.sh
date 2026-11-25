#!/usr/bin/env bash

set -uo pipefail

KEEP_DAYS=30
DRY_RUN=0
QUIET=0
HOOK_ROOT_REL=".observability/claude"
SKILL_USAGE_SCOPE=""
SKILL_USAGE_DIR=".claude/observability"
SKILL_USAGE_DATA_ROOT=""
KEEP_SKILL_USAGE_DAYS=365
FAILURES=0

need_value() {
  [[ $# -ge 2 ]] || {
    echo "ERROR: $1 needs a value (see --help)" >&2
    exit 2
  }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --keep-days=* | --hook-root=* | --skill-usage-scope=* | --skill-usage-dir=* | --skill-usage-data-root=* | --keep-skill-usage-days=*)
    set -- "${1%%=*}" "${1#*=}" "${@:2}"
    ;;
  *) ;;
  esac
  case "$1" in
  --keep-days)
    need_value "$@"
    KEEP_DAYS="$2"
    shift 2
    ;;
  --hook-root)
    need_value "$@"
    HOOK_ROOT_REL="$2"
    shift 2
    ;;
  --skill-usage-scope)
    need_value "$@"
    SKILL_USAGE_SCOPE="$2"
    shift 2
    ;;
  --skill-usage-dir)
    need_value "$@"
    SKILL_USAGE_DIR="$2"
    shift 2
    ;;
  --skill-usage-data-root)
    need_value "$@"
    SKILL_USAGE_DATA_ROOT="$2"
    shift 2
    ;;
  --keep-skill-usage-days)
    need_value "$@"
    KEEP_SKILL_USAGE_DAYS="$2"
    shift 2
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
    cat <<'EOF'
/observability clean: prune local observability data by age (hook JSONL logs, the OTEL
file store, and opt-in skill-usage.jsonl).

Usage:
  bash clean.sh [--keep-days N] [--dry-run] [--quiet] [--hook-root REL]
                [--skill-usage-scope repo|user|data-dir] [--skill-usage-dir REL]
                [--keep-skill-usage-days N]

  --keep-days N               JSONL retention window in days (default: 30); the OTEL store
                              uses CC_OTEL_RETENTION_DAYS / CC_OTEL_BODY_RETENTION_DAYS (7 / 2)
  --dry-run                   report would-prune counts; modify nothing
  --quiet                     suppress progress output (still prints the final summary)
  --hook-root REL             hook log root, project-relative (default .observability/claude)
  --skill-usage-scope SCOPE   prune skill-usage.jsonl: repo, user or data-dir (off when absent)
  --skill-usage-dir REL       the skill-usage directory; required for data-dir
  --keep-skill-usage-days N   skill-usage retention window in days (default: 365)

Exit: 0 success or skip-on-contention; 1 a file could not be pruned or the OTEL prune
failed; 2 a bad argument or no resolvable repository root.
EOF
    exit 0
    ;;
  *)
    echo "ERROR: unknown flag: $1 (see --help)" >&2
    echo "Usage: $0 [--keep-days N] [--dry-run] [--quiet] [--hook-root REL] [--skill-usage-scope repo|user|data-dir] [--skill-usage-dir REL] [--keep-skill-usage-days N]" >&2
    exit 2
    ;;
  esac
done

require_nonneg_int() {
  case "$2" in
  "" | *[!0-9]*)
    echo "ERROR: $1 must be a non-negative integer (got: '$2')" >&2
    exit 2
    ;;
  *) ;;
  esac
}

require_nonneg_int --keep-days "$KEEP_DAYS"

case "$HOOK_ROOT_REL" in
"" | . | ./ | /* | [A-Za-z]:* | ~* | *..* | *\\*)
  echo "ERROR: --hook-root must be a contained relative path below the project root (got: $HOOK_ROOT_REL)" >&2
  exit 2
  ;;
*) ;;
esac
HOOK_ROOT_REL="${HOOK_ROOT_REL%/}"

REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')}"
if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: not in a git repo (and CLAUDE_PROJECT_DIR is unset)" >&2
  exit 2
fi

OBS_DIR="${REPO_ROOT}/.claude/observability"
HOOK_LOG="${OBS_DIR}/hook-events.jsonl"
# shellcheck source=../../../hooks/session-log-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../hooks/session-log-lib.sh"
HOOK_ANCHOR=""
slog_anchor_to HOOK_ANCHOR "$REPO_ROOT"
HOOK_ROOT="${HOOK_ANCHOR}/${HOOK_ROOT_REL}"

cutoff_iso_days_ago() {
  local days="$1" epoch
  # portability-ok: GNU-first dual-dialect probe, BSD branch in the else below (#1510)
  if date -u -d "1 day ago" +%s >/dev/null 2>&1; then
    epoch=$(date -u -d "${days} days ago" +%s) # portability-ok: see if-guard above (#1510)
    date -u -d "@$epoch" +%Y-%m-%dT%H:%M:%SZ   # portability-ok: see if-guard above (#1510)
  else
    epoch=$(date -u -v-"${days}"d +%s)
    date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
  fi
}

CUTOFF_ISO=$(cutoff_iso_days_ago "$KEEP_DAYS")

log() {
  if [[ "$QUIET" -eq 0 ]]; then echo "$@" >&2; fi
}

log "clean: keeping entries on/after $CUTOFF_ISO (--keep-days $KEEP_DAYS)"
[[ "$DRY_RUN" -eq 1 ]] && log "clean: DRY-RUN — no files will be modified"

prune_file() {
  local file="$1" ts_field="$2"
  local CUTOFF_ISO="${3:-$CUTOFF_ISO}"
  local lock_override="${4:-}"
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

  local kept_count
  kept_count=$(jq -c --arg cutoff "$CUTOFF_ISO" --arg ts "$ts_field" \
    'select(.[$ts] >= $cutoff)' "$file" 2>/dev/null | wc -l | tr -d ' \r')

  local pruned=$((before_lines - kept_count))

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if ! jq empty "$file" >/dev/null 2>&1; then
      printf '  %s: %d lines, %d bytes → would skip (a line is not valid JSON)\n' \
        "$label" "$before_lines" "$before_bytes"
      return 0
    fi
    printf '  %s: %d lines, %d bytes → would keep %d, prune %d\n' \
      "$label" "$before_lines" "$before_bytes" "$kept_count" "$pruned"
    return 0
  fi

  if [[ "$pruned" -eq 0 ]]; then
    log "  ${label}: ${before_lines} lines all within window — no change"
    return 0
  fi

  local tmp="${file}.tmp.$$"
  local lock="${lock_override:-${file}.lock}"

  run_jq() {
    jq -c --arg cutoff "$CUTOFF_ISO" --arg ts "$ts_field" \
      'select(.[$ts] >= $cutoff)' "$file" >"$tmp" 2>/dev/null
  }

  local rc=0
  if command -v flock >/dev/null 2>&1; then
    (
      flock -x -w 5 9 || {
        echo "  ${label}: flock timeout — skip (active writer)" >&2
        exit 75
      }
      run_jq && mv -f "$tmp" "$file"
    ) 9>"$lock"
    rc=$?
  else
    run_jq && mv -f "$tmp" "$file"
    rc=$?
  fi
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$tmp" 2>/dev/null
    if [[ "$rc" -ne 75 ]]; then
      echo "  ${label}: jq or mv failed (a line may not be valid JSON) — left unchanged" >&2
      FAILURES=$((FAILURES + 1))
    fi
    return 0
  fi

  local after_lines after_bytes
  after_lines=$(wc -l <"$file" 2>/dev/null | tr -d ' \r')
  after_bytes=$(wc -c <"$file" 2>/dev/null | tr -d ' \r')

  printf '  %s: %d → %d lines (%d pruned); %d → %d bytes\n' \
    "$label" "$before_lines" "$after_lines" "$pruned" "$before_bytes" "$after_bytes"
}

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

prune_file "$HOOK_LOG" "ts"

log "clean: hook log root $HOOK_ROOT"
prune_file "$HOOK_ROOT/hook-events.jsonl" "ts"
prune_file "$HOOK_ROOT/hook-events.jsonl.1" "ts" "" "$HOOK_ROOT/hook-events.jsonl.lock"
if [[ -d "$HOOK_ROOT/sessions" ]]; then
  mapfile -t OLD_SESSIONS < <(
    find "$HOOK_ROOT/sessions" -mindepth 1 -maxdepth 1 -type f -name '*.jsonl' -mmin +"$((KEEP_DAYS * 1440))" 2>/dev/null
  )
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  sessions/: %d file(s) untouched for %d days → would remove\n' "${#OLD_SESSIONS[@]}" "$KEEP_DAYS"
  elif ((${#OLD_SESSIONS[@]} == 0)); then
    log "  sessions/: no file untouched for $KEEP_DAYS days — no change"
  else
    rm -f -- "${OLD_SESSIONS[@]}"
    printf '  sessions/: removed %d file(s) untouched for %d days\n' "${#OLD_SESSIONS[@]}" "$KEEP_DAYS"
  fi
else
  log "  sessions/: missing — skip"
fi
if [[ -d "$HOOK_ROOT/prune-pending" ]]; then
  mapfile -t STALE_PENDING < <(
    find "$HOOK_ROOT/prune-pending" -mindepth 1 -maxdepth 1 -type d -mmin +1440 2>/dev/null
  )
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  prune-pending/: %d set(s) older than 24 h → would sweep\n' "${#STALE_PENDING[@]}"
  elif ((${#STALE_PENDING[@]} == 0)); then
    log "  prune-pending/: nothing older than 24 h — no change"
  else
    rm -rf -- "${STALE_PENDING[@]}"
    printf '  prune-pending/: swept %d set(s) older than 24 h\n' "${#STALE_PENDING[@]}"
  fi
fi

if [[ -n "$SKILL_USAGE_SCOPE" ]]; then
  require_nonneg_int --keep-skill-usage-days "$KEEP_SKILL_USAGE_DAYS"

  case "$SKILL_USAGE_DIR" in
  /* | [A-Za-z]:* | *..*)
    echo "ERROR: --skill-usage-dir must be a contained relative path (got: $SKILL_USAGE_DIR)" >&2
    exit 2
    ;;
  *) ;;
  esac

  SKILL_USAGE_BASE=""
  case "$SKILL_USAGE_SCOPE" in
  repo) SKILL_USAGE_BASE="$REPO_ROOT" ;;
  user) SKILL_USAGE_BASE="${HOME:-}" ;;
  data-dir)
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

  if [[ "$SKILL_USAGE_SCOPE" != "data-dir" && -z "$SKILL_USAGE_BASE" ]]; then
    echo "ERROR: could not resolve a base directory for scope $SKILL_USAGE_SCOPE" >&2
    exit 2
  fi

  SU_CUTOFF_ISO=$(cutoff_iso_days_ago "$KEEP_SKILL_USAGE_DAYS")

  if [[ "$SKILL_USAGE_SCOPE" == "data-dir" ]]; then
    # shellcheck source=../../../hooks/hook-utils.sh
    . "${SKILL_DIR}/../../hooks/hook-utils.sh"
    # shellcheck source=../../../hooks/harness-ops-paths.sh
    . "${SKILL_DIR}/../../hooks/harness-ops-paths.sh"
    SKILL_USAGE_LOG="${SKILL_USAGE_DATA_ROOT%/}/skill-usage/$(harness_ops::repo_slug "$REPO_ROOT")/skill-usage.jsonl"
  else
    SKILL_USAGE_LOG="${SKILL_USAGE_BASE%/}/${SKILL_USAGE_DIR}/skill-usage.jsonl"
  fi
  log "clean: skill-usage (scope $SKILL_USAGE_SCOPE, keeping on/after $SU_CUTOFF_ISO, --keep-skill-usage-days $KEEP_SKILL_USAGE_DAYS)"
  log "clean: skill-usage target $SKILL_USAGE_LOG"
  prune_file "$SKILL_USAGE_LOG" "ts" "$SU_CUTOFF_ISO"
fi

PRUNE_OTEL="${SKILL_DIR}/otel/prune-otel-store.sh"
if [[ -f "$PRUNE_OTEL" ]]; then
  log "clean: OTEL store (CC_OTEL_RETENTION_DAYS=${CC_OTEL_RETENTION_DAYS:-7}, CC_OTEL_BODY_RETENTION_DAYS=${CC_OTEL_BODY_RETENTION_DAYS:-2}; stops Collector only if records exceed a window)"
  export CC_OTEL_STORE="${CC_OTEL_STORE:-$REPO_ROOT/.claude/observability/otel}"
  otel_args=()
  [[ "$DRY_RUN" -eq 1 ]] && otel_args=(--dry-run)
  bash "$PRUNE_OTEL" "${otel_args[@]}" || {
    echo "  prune-otel-store.sh: returned non-zero (OTEL store may be unchanged)" >&2
    FAILURES=$((FAILURES + 1))
  }
else
  log "  prune-otel-store.sh: not found — skipping OTEL store"
fi

if ((FAILURES > 0)); then
  echo "clean: done with $FAILURES failure(s); see the messages above" >&2
  exit 1
fi
log "clean: done"
