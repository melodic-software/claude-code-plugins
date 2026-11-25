#!/usr/bin/env bash

set -euo pipefail

readonly DEFAULT_CC_OTEL_RETENTION_DAYS=7
readonly DEFAULT_CC_OTEL_BODY_RETENTION_DAYS=2
readonly DEFAULT_CC_OTEL_HOT_MAX_MB=1024
readonly DEFAULT_CC_OTEL_HOT_TOTAL_MAX_MB=1024
readonly BYTES_PER_MB=1048576
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
Usage: prune-otel-store.sh [--scrub-cold] [--dry-run] [--help]

Age-based, per-class retention for the local Claude Code OTEL file store, stopping +
restarting the machine-singleton Collector around an in-place trim. Structure records age
out at CC_OTEL_RETENTION_DAYS (default 7); api_*_body records at CC_OTEL_BODY_RETENTION_DAYS
(default 2) — lines past the body window but inside the structure window are surgically
stripped of their body records (jq), sibling structure records survive. Whole lines past the
structure window are first compacted to the cold Parquet tier (<store>/cold/, structure-only
for logs) — a compaction or surgery failure aborts BEFORE the trim. Verify-before-replace: a
store file is only ever replaced by a temp that parses.

Options:
  --dry-run     Report cutoffs, the size caps + per-file per-class counts; never stop the Collector or mutate.
  --scrub-cold  Rewrite cold files that still hold content the cold switches scrub (prompt,
                prompt_text, user_prompt; with CC_OTEL_COLD_KEEP_CONTENT=0 also the content-class
                columns, metrics included) with the compaction scrub; row counts are verified
                before replace. With --dry-run, list affected files and row counts only.
  --help        Show this help.

Env:
  CC_OTEL_RETENTION_DAYS       keep structure records newer than N days (default: 7)
  CC_OTEL_BODY_RETENTION_DAYS  keep api_*_body records newer than N days (default: 2; must
                               not exceed the structure window)
  CC_OTEL_HOT_MAX_MB           size cap per hot file in MiB (default: 1024; 0 disables): a file
                               over the cap drops its oldest lines, via cold, until it fits
  CC_OTEL_HOT_TOTAL_MAX_MB     size cap across all hot files in MiB (default: 1024; 0 disables):
                               over it, the oldest lines across the files drop, via cold, until they fit
  CC_OTEL_STORE                absolute store dir (default: <repo-root>/.claude/observability/otel)
  CC_OTEL_COLD_KEEP_USER_PROMPTS
                               =1 keeps user_prompt bodies + prompt/prompt_text attributes in cold (default: off)
  CC_OTEL_COLD_KEEP_CONTENT    =0 scrubs the other content-class columns in cold (default: 1, kept)
  CC_OTEL_SENTINEL_MAX_AGE_MINUTES
                               stale-lock bound in minutes (default: 60)
  Lifecycle                    Windows service: otelcol-contrib (requires provisioning's scoped
                               SERVICE_STOP and SERVICE_START grant for the runtime user)
EOF
}

resolve_repo_root() {
  local root="${CLAUDE_PROJECT_DIR:-}"
  [[ -n "$root" ]] || root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r' || true)"
  printf '%s\n' "${root:-$(pwd)}"
}

time_field() {
  if [[ "${1##*/}" == cc-traces.json ]]; then
    printf 'startTimeUnixNano\n'
  else
    printf 'timeUnixNano\n'
  fi
}

filter_file() {
  local src="$1" dst="$2" cutoff_seconds="$3" dropped_dst="${4:-}"
  local body_cutoff_seconds="${5:-0}" surgery_dst="${6:-}"
  awk -v cutoff="$cutoff_seconds" -v body_cutoff="$body_cutoff_seconds" \
    -v dst="$dst" -v ddst="$dropped_dst" -v sdst="$surgery_dst" -v tf="$(time_field "$src")" \
    -f "$SCRIPT_DIR/prune-filter.awk" "$src"
}

file_bytes() {
  local size
  size="$(wc -c <"$1")"
  printf '%s\n' "${size//[[:space:]]/}"
}

line_sizes() {
  LC_ALL=C awk -v tf="$(time_field "$1")" '
    match($0, "\"" tf "\":\"[0-9]+\"") {
      prefix_len = length(tf) + 4
      ns = substr($0, RSTART + prefix_len, RLENGTH - prefix_len - 1)
      print substr(ns, 1, length(ns) - 9), length($0) + 1
    }' "$1"
}

size_cut() {
  sort -rn | awk -v cap="$1" '!cut { acc += $2; if (acc > cap) { print $1 + 1; cut = 1 } }'
}

total_cutoff() {
  local cap_bytes="$1" src total=0
  shift
  ((cap_bytes > 0)) || return 0
  for src in "$@"; do
    total=$((total + $(file_bytes "$src")))
  done
  ((total > cap_bytes)) || return 0
  for src in "$@"; do
    line_sizes "$src"
  done | size_cut "$cap_bytes"
}

effective_cutoff() {
  local src="$1" cutoff_seconds="$2" cap_bytes="$3" total_cut="${4:-}"
  local cut="" best="$cutoff_seconds" size
  size="$(file_bytes "$src")"
  if ((cap_bytes > 0 && size > cap_bytes)); then
    cut="$(line_sizes "$src" | size_cut "$cap_bytes")"
  fi
  if [[ -n "$cut" ]] && ((cut > best)); then
    best="$cut"
  fi
  if [[ -n "$total_cut" ]] && ((total_cut > best)); then
    best="$total_cut"
  fi
  printf '%s\n' "$best"
}

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

real_path() {
  local p="$1" tail=""
  while [[ ! -d "$p" && "$p" == */* ]]; do
    tail="/${p##*/}$tail"
    p="${p%/*}"
  done
  [[ "$tail/" != */../* ]] || return 0 # unresolvable: prints nothing, which no root contains
  p="$(cd "${p:-/}" && pwd -P)"
  if command -v cygpath >/dev/null 2>&1; then p="$(cygpath -aml "$p")"; fi
  printf '%s%s\n' "${p%/}" "$tail"
}

under_root() {
  local path root
  path="$(real_path "$1")"
  root="$(real_path "$2")"
  [[ "${path%/}/" == "${root%/}/"* ]]
}

take_lock_or_report() {
  local rc=0
  # shellcheck disable=SC2310  # failure IS the handled branch; set -e suppression is intended
  acquire_sentinel || rc=$?
  ((rc == 0)) && return 0
  if ((rc == 3)); then
    lock_held_too_long
    printf 'action=error-lock-held\n'
  else
    err "a prune is already in progress ($SENTINEL) — exiting"
    printf 'action=noop-locked\n'
  fi
  return "$rc"
}

stamp_last_prune() { date -u +%Y-%m-%dT%H:%M:%SZ >"$1/.last-prune"; }

main() {
  local dry_run=false scrub_cold_mode=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=true ;;
      --scrub-cold) scrub_cold_mode=true ;;
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
  local hot_max_mb="${CC_OTEL_HOT_MAX_MB:-$DEFAULT_CC_OTEL_HOT_MAX_MB}"
  if [[ ! "$hot_max_mb" =~ ^[0-9]+$ ]]; then
    err "CC_OTEL_HOT_MAX_MB must be a non-negative integer (got: $hot_max_mb)"
    return 2
  fi
  local hot_total_max_mb="${CC_OTEL_HOT_TOTAL_MAX_MB:-$DEFAULT_CC_OTEL_HOT_TOTAL_MAX_MB}"
  if [[ ! "$hot_total_max_mb" =~ ^[0-9]+$ ]]; then
    err "CC_OTEL_HOT_TOTAL_MAX_MB must be a non-negative integer (got: $hot_total_max_mb)"
    return 2
  fi
  if [[ ! "$SENTINEL_MAX_AGE_MINUTES" =~ ^[1-9][0-9]*$ ]]; then
    err "CC_OTEL_SENTINEL_MAX_AGE_MINUTES must be a positive integer (got: $SENTINEL_MAX_AGE_MINUTES)"
    return 2
  fi
  hot_max_mb=$((10#$hot_max_mb))
  hot_total_max_mb=$((10#$hot_total_max_mb))
  if ((body_retention_days > retention_days)); then
    err "CC_OTEL_BODY_RETENTION_DAYS ($body_retention_days) must not exceed CC_OTEL_RETENTION_DAYS ($retention_days)"
    return 2
  fi

  local repo_root store_dir cutoff_seconds body_cutoff_seconds
  repo_root="$(resolve_repo_root)"
  store_dir="${CC_OTEL_STORE:-$repo_root/.claude/observability/otel}"
  [[ "$OS_KIND" == windows ]] && store_dir="${store_dir//\\//}"
  # shellcheck disable=SC2310  # a predicate: its status IS the branch
  if [[ -n "${CC_OTEL_TEST_ROOT:-}" ]] && ! under_root "$store_dir" "$CC_OTEL_TEST_ROOT"; then
    err "store $store_dir is outside CC_OTEL_TEST_ROOT ($CC_OTEL_TEST_ROOT) — refusing"
    return 2
  fi
  SENTINEL="$store_dir/.prune-in-progress"

  if [[ "$scrub_cold_mode" == true ]]; then
    printf 'store_dir=%s\n' "$store_dir"
    # shellcheck disable=SC2310  # predicates: their status IS the branch
    if keep_prompts && ! scrub_content; then
      printf 'CC_OTEL_COLD_KEEP_USER_PROMPTS=1 and CC_OTEL_COLD_KEEP_CONTENT (unset or 1) keep prompts and content in cold; nothing scrubbed\n'
      printf 'action=noop-scrub-cold-keep-user-prompts\n'
      [[ "$dry_run" == true ]] || ensure_collector_briefly
      return
    fi
    if ! command -v duckdb >/dev/null 2>&1; then
      err "duckdb not found — cannot scrub cold files"
      printf 'action=error-duckdb-missing\n'
      return 1
    fi
    if [[ "$dry_run" == true ]]; then
      scrub_cold "$store_dir" true
      return
    fi
    mkdir -p "$store_dir"
    # shellcheck disable=SC2310  # failure IS the handled branch; set -e suppression is intended
    take_lock_or_report || return $(($? == 3))
    OWN_SENTINEL=true
    trap cleanup EXIT
    rm -f "$store_dir/cold/"*.tmp 2>/dev/null || true
    ensure_collector_running
    scrub_cold "$store_dir" false
    return
  fi

  cutoff_seconds=$((EPOCHSECONDS - retention_days * SECONDS_PER_DAY))
  body_cutoff_seconds=$((EPOCHSECONDS - body_retention_days * SECONDS_PER_DAY))

  printf 'store_dir=%s\n' "$store_dir"
  printf 'retention_days=%s\n' "$retention_days"
  printf 'body_retention_days=%s\n' "$body_retention_days"
  printf 'hot_max_mb=%s\n' "$hot_max_mb"
  printf 'hot_total_max_mb=%s\n' "$hot_total_max_mb"
  printf 'cutoff_epoch_seconds=%s\n' "$cutoff_seconds"
  printf 'body_cutoff_epoch_seconds=%s\n' "$body_cutoff_seconds"

  local f src
  local -a present_files=() present_paths=()
  for f in "${STORE_FILES[@]}"; do
    src="$store_dir/$f"
    if [[ ! -f "$src" ]]; then
      printf '%s: absent (skipped)\n' "$f"
      continue
    fi
    present_files+=("$f")
    present_paths+=("$src")
  done
  local hot_max_bytes=$((hot_max_mb * BYTES_PER_MB)) hot_total_max_bytes=$((hot_total_max_mb * BYTES_PER_MB))
  local total_cut
  total_cut="$(total_cutoff "$hot_total_max_bytes" "${present_paths[@]}")"
  if [[ -n "$total_cut" ]] && ((total_cut > cutoff_seconds)); then
    printf 'hot_total: size_prune cutoff_epoch_seconds=%s\n' "$total_cut"
  fi

  local counts file_cutoff age_dropped total_dropped=0 total_surgery=0 size_pruned=0
  local -A file_cutoffs=()
  for f in "${present_files[@]}"; do
    src="$store_dir/$f"
    file_cutoff="$(effective_cutoff "$src" "$cutoff_seconds" "$hot_max_bytes" "$total_cut")"
    file_cutoffs["$f"]="$file_cutoff"
    age_dropped=0
    if ((file_cutoff > cutoff_seconds)); then
      counts="$(filter_file "$src" "" "$cutoff_seconds" "" "$body_cutoff_seconds" "")"
      parse_counts "$counts"
      age_dropped="$DROPPED"
    fi
    counts="$(filter_file "$src" "" "$file_cutoff" "" "$body_cutoff_seconds" "")"
    parse_counts "$counts"
    if ((file_cutoff > cutoff_seconds && DROPPED > age_dropped)); then
      size_pruned=$((size_pruned + 1))
      printf '%s: size_prune cutoff_epoch_seconds=%s\n' "$f" "$file_cutoff"
    fi
    printf '%s: %s\n' "$f" "$counts"
    total_dropped=$((total_dropped + DROPPED))
    total_surgery=$((total_surgery + SURGERY))
  done
  cold_prompt_notice "$store_dir"

  if [[ "$dry_run" == true ]]; then
    printf 'action=dry-run total_dropped=%s total_surgery=%s size_pruned_files=%s\n' "$total_dropped" "$total_surgery" "$size_pruned"
    return 0
  fi
  mark_cold_clean_briefly "$store_dir"

  if ((${#present_files[@]} == 0)); then
    printf 'action=noop-store-absent\n'
    ensure_collector_briefly
    return
  fi

  if ((total_dropped == 0 && total_surgery == 0)); then
    stamp_last_prune "$store_dir"
    printf 'action=noop-nothing-to-prune\n'
    ensure_collector_briefly
    return
  fi

  mkdir -p "$store_dir"
  # shellcheck disable=SC2310  # failure IS the handled branch; set -e suppression is intended
  take_lock_or_report || return $(($? == 3))
  OWN_SENTINEL=true
  trap cleanup EXIT
  mark_cold_clean "$store_dir"

  rm -f "$store_dir/cold/"*.tmp 2>/dev/null || true

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

  local cold_ts
  cold_ts="$(date -u +%Y%m%dT%H%M%SZ)"

  total_cut="$(total_cutoff "$hot_total_max_bytes" "${present_paths[@]}")"
  local temp dropped surgery_tmp surgery_counts surgery_kept surgery_dropped
  for f in "${present_files[@]}"; do
    src="$store_dir/$f"
    temp="$src.prune.tmp"
    dropped="$src.dropped.tmp"
    surgery_tmp="$src.surgery.tmp"
    file_cutoffs["$f"]="$(effective_cutoff "$src" "$cutoff_seconds" "$hot_max_bytes" "$total_cut")"
    counts="$(filter_file "$src" "$temp" "${file_cutoffs[$f]}" "$dropped" "$body_cutoff_seconds" "$surgery_tmp")"
    [[ -f "$temp" ]] || : >"$temp"
    parse_counts "$counts"
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

  STAMP_DIR="$store_dir"
  printf 'action=pruned total_dropped=%s total_surgery=%s\n' "$total_dropped" "$total_surgery"
}

main "$@"
