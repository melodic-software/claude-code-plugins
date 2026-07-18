#!/usr/bin/env bash
# prune-otel-store.sh — age-based, per-class retention for the local Claude Code OTEL store.
#
# Bounds the persistent store (.claude/observability/otel/{cc-logs,cc-metrics,cc-traces}.json)
# retention windows, coordinating safely with the machine-singleton Collector. The store files
# are newline-delimited OTLP-JSON (one ExportXServiceRequest batch per line); a line's age is
# its FIRST timeUnixNano (the earliest record in the batch).
#
# Per-class retention (record-granular): content-bearing body events
# (api_request_body/api_response_body) age out at CC_OTEL_BODY_RETENTION_DAYS (default 2);
# everything else at CC_OTEL_RETENTION_DAYS (default 7). 97% of body-bearing batch lines also
# carry structure events, so the body window cannot drop whole lines — lines past the body
# window but inside the structure window get jq SURGERY: api_*_body logRecords are stripped,
# sibling structure records survive (re-serialized by jq, re-appended after the kept lines —
# NDJSON order is not load-bearing, views sort by event_time). Lines past the structure
# window drop whole, compacting to cold first.
#
# Lock-safe cycle (only runs when records actually need dropping — see dry-check below):
#   1. acquire an mkdir-atomic sentinel (.prune-in-progress) in the store dir. The mkdir is the
#      mutual-exclusion lock: a second prune fails to create it and exits without mutation.
#   2. stop the provisioning-owned otelcol-contrib Windows service; poll Get-Service until it is
#      Stopped so its file exporter has released the store handles.
#   3. per store file: awk-route each line to a kept temp / dropped temp / surgery temp in the
#      SAME dir, COMPACT the dropped (aged-out) lines to a cold Parquet file under
#      <store>/cold/ (see compact_dropped in prune-compact.sh — content-scrubbed for logs,
#      verbatim for metrics), SURGERY the body-aged lines (see surgery_file — jq strips
#      api_*_body records, survivors re-append to the kept temp), VERIFY the kept temp parses
#      via `duckdb read_json_auto`, then atomic `mv` over the original. Compact-before-trim +
#      verify-before-replace: the original is only ever replaced after its aged records are
#      safely in cold AND by a verified-good temp, so a failure at any point leaves the hot
#      store intact — no backup/rollback needed.
#   4. start the service + release the sentinel last. Done in the EXIT trap, so every trim exit path
#      attempts recovery; a failed restart makes an otherwise successful prune fail visibly.
#
# Comparison is at SECOND granularity: a 19-digit nano (~1.78e18) exceeds awk's exact-integer
# range (IEEE-754 double, exact only to 2^53 ≈ 9.0e15), so a raw-nano awk compare silently
# loses precision. Stripping the last 9 digits yields seconds (~1.78e9, well under 2^53, exact).
# The match regex is case-sensitive + leading-quote-anchored ("timeUnixNano":"...) so it never
# matches the sibling observedTimeUnixNano (logs) / startTimeUnixNano (metrics) fields.
#
# --dry-run reports the cutoffs + per-file per-class counts (kept / dropped / surgery /
# body_dropped / would_compact) and never stops the Collector or mutates a file. A real run
# also short-circuits (no stop/trim/restart) when nothing is below either cutoff, avoiding
# needless Collector churn.
#
# Usage:
#   bash prune-otel-store.sh             # prune if needed (stop/trim/restart)
#   bash prune-otel-store.sh --dry-run   # report only, never mutate
#   bash prune-otel-store.sh --help
#
# Env overrides:
#   CC_OTEL_RETENTION_DAYS keep structure records newer than N days (default: 7).
#                          RETENTION_DAYS alone is rejected with exit 2.
#   CC_OTEL_BODY_RETENTION_DAYS
#                          keep api_*_body records newer than N days (default: 2); must not
#                          exceed CC_OTEL_RETENTION_DAYS (body records cannot outlive their
#                          lines)
#   CC_OTEL_STORE          absolute store dir (default: <repo-root>/.claude/observability/otel)
#   CC_OTEL_COLD_KEEP_USER_PROMPTS
#                          =1 keeps user_prompt bodies + the `prompt` attribute in the cold
#                          tier un-scrubbed (default: off — body NULLed, prompt scrubbed)
#   CC_OTEL_START_CMD      command that starts the Collector service — hermetic test seam
#   CC_OTEL_STOP_CMD       command that stops the Collector service — hermetic test seam
#   CC_OTEL_RUNNING_CMD    service query command: exit 0 = running/not Stopped, 1 = Stopped,
#                          2+ = query error — hermetic test seam
#   CC_OTEL_VERIFY_CMD     command (receives temp path as $1) exiting 0 iff the temp parses
#                          (default: duckdb read_json_auto) — test seam
#   CC_OTEL_COMPACT_CMD    command (receives <dropped-temp> <cold-temp>) replacing the duckdb
#                          cold COPY+verify; must create <cold-temp> on success — test seam
#                          (failure injection ONLY; real compaction is always duckdb)

set -euo pipefail

readonly DEFAULT_CC_OTEL_RETENTION_DAYS=7
readonly DEFAULT_CC_OTEL_BODY_RETENTION_DAYS=2
readonly SECONDS_PER_DAY=86400
readonly STORE_FILES=("cc-logs.json" "cc-metrics.json" "cc-traces.json")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

err() { printf 'prune-otel-store.sh: %s\n' "$*" >&2; }

# shellcheck source=./prune-collector-lifecycle.sh
source "$SCRIPT_DIR/prune-collector-lifecycle.sh"
# shellcheck source=./prune-compact.sh
source "$SCRIPT_DIR/prune-compact.sh"

usage() {
  cat <<'EOF'
Usage: prune-otel-store.sh [--dry-run] [--help]

Age-based, per-class retention for the local Claude Code OTEL file store, stopping +
restarting the machine-singleton Collector around an in-place trim. Structure records age
out at CC_OTEL_RETENTION_DAYS (default 7); api_*_body records at CC_OTEL_BODY_RETENTION_DAYS
(default 2) — lines past the body window but inside the structure window are surgically
stripped of their body records (jq), sibling structure records survive. Whole lines past the
structure window are first compacted to the cold Parquet tier (<store>/cold/, structure-only
for logs) — a compaction or surgery failure aborts BEFORE the trim. Verify-before-replace: a
store file is only ever replaced by a temp that parses.

Options:
  --dry-run   Report cutoffs + per-file per-class counts; never stop the Collector or mutate.
  --help      Show this help.

Env:
  CC_OTEL_RETENTION_DAYS       keep structure records newer than N days (default: 7)
  CC_OTEL_BODY_RETENTION_DAYS  keep api_*_body records newer than N days (default: 2; must
                               not exceed the structure window)
  CC_OTEL_STORE                absolute store dir (default: <repo-root>/.claude/observability/otel)
  CC_OTEL_COLD_KEEP_USER_PROMPTS
                               =1 keeps user_prompt bodies + prompt attribute in cold (default: off)
  Lifecycle                    Windows service: otelcol-contrib (requires provisioning's scoped
                               SERVICE_STOP and SERVICE_START grant for the runtime user)
EOF
}

# Resolve the consumer project root so prune + duckdb queries resolve the same fallback store:
# CLAUDE_PROJECT_DIR when the harness sets it, else the git worktree containing the CWD, else CWD.
resolve_repo_root() {
  local root
  root="${CLAUDE_PROJECT_DIR:-}"
  if [[ -z "$root" ]]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r' || true)"
  fi
  if [[ -z "$root" ]]; then
    root="$(pwd)"
  fi
  printf '%s\n' "$root"
}

# Route one store file's lines 3 ways by the batch's first timestamp field (single awk pass).
# See prune-filter.awk for routing rules and count format.
filter_file() {
  local src="$1" dst="$2" cutoff_seconds="$3" dropped_dst="${4:-}"
  local body_cutoff_seconds="${5:-0}" surgery_dst="${6:-}" time_field="${7:-timeUnixNano}"
  awk -v cutoff="$cutoff_seconds" -v body_cutoff="$body_cutoff_seconds" \
    -v dst="$dst" -v ddst="$dropped_dst" -v sdst="$surgery_dst" -v tf="$time_field" \
    -f "$SCRIPT_DIR/prune-filter.awk" "$src"
}

# Read "kept=.. dropped=.. total=.. surgery=.." into the named-by-convention globals
# KEPT/DROPPED/TOTAL/SURGERY. (#*dropped= strips the SHORTEST prefix, so it lands on the
# first occurrence — never the body_dropped= field later in the line.)
parse_counts() {
  local line="$1"
  KEPT="${line#*kept=}"
  KEPT="${KEPT%% *}"
  DROPPED="${line#*dropped=}"
  DROPPED="${DROPPED%% *}"
  TOTAL="${line#*total=}"
  TOTAL="${TOTAL%% *}"
  SURGERY="${line#*surgery=}"
  SURGERY="${SURGERY%% *}"
}

main() {
  local dry_run=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --help | -h)
        usage
        return 0
        ;;
      *)
        err "unknown argument: $1"
        usage >&2
        return 2
        ;;
    esac
    shift
  done

  # RETENTION_DAYS guard: bare RETENTION_DAYS with CC_OTEL_RETENTION_DAYS unset exits 2.
  if [[ -n "${RETENTION_DAYS:-}" && -z "${CC_OTEL_RETENTION_DAYS:-}" ]]; then
    err "RETENTION_DAYS is not read — use CC_OTEL_RETENTION_DAYS (body window: CC_OTEL_BODY_RETENTION_DAYS). Unset RETENTION_DAYS."
    return 2
  fi

  local retention_days="${CC_OTEL_RETENTION_DAYS:-$DEFAULT_CC_OTEL_RETENTION_DAYS}"
  local body_retention_days="${CC_OTEL_BODY_RETENTION_DAYS:-$DEFAULT_CC_OTEL_BODY_RETENTION_DAYS}"
  if [[ ! "$retention_days" =~ ^[0-9]+$ ]]; then
    err "CC_OTEL_RETENTION_DAYS must be a non-negative integer (got: $retention_days)"
    return 2
  fi
  if [[ ! "$body_retention_days" =~ ^[0-9]+$ ]]; then
    err "CC_OTEL_BODY_RETENTION_DAYS must be a non-negative integer (got: $body_retention_days)"
    return 2
  fi
  # Reject, don't clamp: body records cannot outlive the lines that carry them.
  if ((body_retention_days > retention_days)); then
    err "CC_OTEL_BODY_RETENTION_DAYS ($body_retention_days) must not exceed CC_OTEL_RETENTION_DAYS ($retention_days)"
    return 2
  fi

  local repo_root store_dir cutoff_seconds body_cutoff_seconds
  repo_root="$(resolve_repo_root)"
  store_dir="${CC_OTEL_STORE:-$repo_root/.claude/observability/otel}"
  SENTINEL="$store_dir/.prune-in-progress"
  cutoff_seconds=$((EPOCHSECONDS - retention_days * SECONDS_PER_DAY))
  body_cutoff_seconds=$((EPOCHSECONDS - body_retention_days * SECONDS_PER_DAY))

  printf 'store_dir=%s\n' "$store_dir"
  printf 'retention_days=%s\n' "$retention_days"
  printf 'body_retention_days=%s\n' "$body_retention_days"
  printf 'cutoff_epoch_seconds=%s\n' "$cutoff_seconds"
  printf 'body_cutoff_epoch_seconds=%s\n' "$body_cutoff_seconds"

  # Per-file per-class counts (dry-check decides whether a real run needs the
  # stop/trim/restart at all). The awk output line IS the report format.
  local f src counts total_dropped=0 total_surgery=0
  local -a present_files=()
  for f in "${STORE_FILES[@]}"; do
    src="$store_dir/$f"
    if [[ ! -f "$src" ]]; then
      printf '%s: absent (skipped)\n' "$f"
      continue
    fi
    present_files+=("$f")
    local time_field="timeUnixNano"
    [[ "$f" == cc-traces.json ]] && time_field="startTimeUnixNano"
    counts="$(filter_file "$src" "" "$cutoff_seconds" "" "$body_cutoff_seconds" "" "$time_field")"
    parse_counts "$counts"
    printf '%s: %s\n' "$f" "$counts"
    total_dropped=$((total_dropped + DROPPED))
    total_surgery=$((total_surgery + SURGERY))
  done

  if [[ "$dry_run" == true ]]; then
    printf 'action=dry-run total_dropped=%s total_surgery=%s\n' "$total_dropped" "$total_surgery"
    return 0
  fi

  if ((${#present_files[@]} == 0)); then
    printf 'action=noop-store-absent\n'
    return 0
  fi

  # Dry-check short-circuit: nothing below either cutoff => no Collector churn.
  if ((total_dropped == 0 && total_surgery == 0)); then
    printf 'action=noop-nothing-to-prune\n'
    return 0
  fi

  # Acquire the mkdir-atomic sentinel (lock + revival-race signal). Failure => another prune holds it.
  mkdir -p "$store_dir"
  if ! mkdir "$SENTINEL" 2>/dev/null; then
    err "a prune is already in progress ($SENTINEL) — exiting"
    printf 'action=noop-locked\n'
    return 0
  fi
  OWN_SENTINEL=true
  trap cleanup EXIT

  # Sweep stale cold temps left by a previous hard-killed run (safe: we hold the lock, so no
  # live compaction can own them). The .tmp suffix never matches the cold *-*.parquet glob.
  rm -f "$store_dir/cold/"*.tmp 2>/dev/null || true

  # Stop the Collector service, then wait for its Stopped state (and released file handles).
  stop_collector
  STOPPED=true
  local wait_rc
  # shellcheck disable=SC2310  # failure IS the handled branch; set -e suppression is intended
  if wait_collector_gone; then
    :
  else
    wait_rc=$?
    if ((wait_rc == 2)); then
      err "failed to query Collector service status — aborting before trim (store untouched)"
      printf 'action=error-collector-status-query\n'
    else
      err "Collector still running after stop — aborting before trim (store untouched)"
      printf 'action=error-collector-not-stopped\n'
    fi
    return 1
  fi

  # One timestamp per run: the logs + metrics cold files of the same prune share it.
  local cold_ts
  cold_ts="$(date -u +%Y%m%dT%H%M%SZ)"

  # Trim each present file: route -> kept/dropped/surgery temps (same dir) -> compact dropped
  # lines to cold Parquet -> surgery body-aged lines (survivors re-append to the kept temp)
  # -> verify kept temp -> atomic mv. Compact-before-trim: the cold mv lands BEFORE the hot
  # mv, so every failure path (compact, surgery, verify) leaves the original hot file intact.
  local temp dropped surgery_tmp surgery_counts surgery_kept surgery_dropped
  for f in "${present_files[@]}"; do
    src="$store_dir/$f"
    temp="$src.prune.tmp"
    dropped="$src.dropped.tmp"
    surgery_tmp="$src.surgery.tmp"
    local time_field="timeUnixNano"
    [[ "$f" == cc-traces.json ]] && time_field="startTimeUnixNano"
    counts="$(filter_file "$src" "$temp" "$cutoff_seconds" "$dropped" "$body_cutoff_seconds" "$surgery_tmp" "$time_field")"
    # awk only opens dst when it prints a kept line, so a file with ZERO kept records (every
    # record older than the cutoff — the case retention exists for) leaves the temp absent.
    # Create it empty: an empty store is the correct all-aged-out end-state (append:true refills
    # on restart), and this keeps surgery_file + verify_temp + mv operating on a real path.
    [[ -f "$temp" ]] || : >"$temp"
    parse_counts "$counts"
    # Compact BEFORE the hot trim. The dropped temp can be absent/empty even when DROPPED > 0
    # (unparsable partial lines count as dropped but are not routed) — nothing to compact then.
    if [[ -s "$dropped" ]]; then
      # shellcheck disable=SC2310  # failure IS the handled branch; set -e suppression is intended
      if ! compact_dropped "$f" "$dropped" "$store_dir" "$cold_ts"; then
        rm -f "$temp" "$dropped" "$surgery_tmp"
        err "cold compaction failed for $f — aborting before trim (original untouched)"
        printf 'action=error-compact-failed file=%s\n' "$f"
        return 1
      fi
    fi
    rm -f "$dropped"
    surgery_kept=0
    surgery_dropped=0
    if [[ -s "$surgery_tmp" ]]; then
      # shellcheck disable=SC2310  # failure IS the handled branch; set -e suppression is intended
      if ! surgery_counts="$(surgery_file "$surgery_tmp" "$temp")"; then
        rm -f "$temp" "$surgery_tmp"
        err "body-record surgery failed for $f — aborting before trim (original untouched)"
        printf 'action=error-surgery-failed file=%s\n' "$f"
        return 1
      fi
      surgery_kept="${surgery_counts#*surgery_kept=}"
      surgery_kept="${surgery_kept%% *}"
      surgery_dropped="${surgery_counts#*surgery_dropped=}"
      surgery_dropped="${surgery_dropped%% *}"
    fi
    rm -f "$surgery_tmp"
    # shellcheck disable=SC2310  # failure IS the handled branch; set -e suppression is intended
    if ! verify_temp "$temp"; then
      rm -f "$temp"
      err "verification failed for $f — aborting (original untouched)"
      printf 'action=error-verify-failed file=%s\n' "$f"
      return 1
    fi
    mv -f "$temp" "$src"
    printf '%s: pruned kept=%s dropped=%s total=%s surgery_kept=%s surgery_dropped=%s\n' \
      "$f" "$KEPT" "$DROPPED" "$TOTAL" "$surgery_kept" "$surgery_dropped"
  done

  printf 'action=pruned total_dropped=%s total_surgery=%s\n' "$total_dropped" "$total_surgery"
  # cleanup (EXIT trap) removes the sentinel and starts the Collector service.
}

main "$@"
