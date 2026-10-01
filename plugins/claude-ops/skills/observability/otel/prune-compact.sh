#!/usr/bin/env bash
# prune-compact.sh — duckdb cold compaction, verify, and jq body surgery.
# Sourced by prune-otel-store.sh; not an entry point.
#
# Requires SCRIPT_DIR, OS_KIND, and err() from the caller.
# shellcheck disable=SC2154  # SCRIPT_DIR and OS_KIND are set by prune-otel-store.sh before source.

# maximum_object_size matches cc-otel.sql (32 MiB — generous over the ~224 KB largest inline-body record).
readonly DUCKDB_MAX_OBJECT_SIZE=33554432

# Prompt-bearing attribute keys the cold tier scrubs (SQL list items). Compaction and
# --scrub-cold both read these, so a new key added here reaches both.
readonly COLD_LOG_PROMPT_KEYS="'prompt', 'prompt_text'"
readonly COLD_SPAN_PROMPT_KEYS="'user_prompt', 'prompt', 'prompt_text'"
# from_json shape of a serialized attributes list; value stays raw JSON so it round-trips.
readonly COLD_ATTR_SHAPE='[{"key":"VARCHAR","value":"JSON"}]'

# Convert a path for embedding in a SQL string literal (or as a duckdb CLI arg). Native
# duckdb.exe cannot resolve an MSYS path (/tmp/..., /d/...); cygpath -m yields a forward-slash
# Windows path (C:/...) — safe in a SQL string literal and idempotent on an already-Windows
# path (D:/...). No-op on POSIX (cygpath absent).
sql_path() {
  local p="$1"
  if [[ "$OS_KIND" == windows ]] && command -v cygpath >/dev/null 2>&1; then
    p="$(cygpath -m "$p")"
  fi
  # SQL-literal safety: callers interpolate this inside '...' — double any
  # single quote so a path like /tmp/O'Neil cannot break the literal.
  printf '%s\n' "${p//\'/\'\'}"
}

# Run a command with stdout discarded; on failure pass its stderr to err() so the cause is
# visible instead of a bare "failed". A duckdb -init load also reports the expected hot-view bind
# errors (see compact_dropped); the failing statement's error comes last.
run_reporting() {
  local out label=("$@")
  [[ "${label[0]}" == env ]] && label=("${label[@]:1}")
  while [[ "${label[0]}" == *=* ]]; do label=("${label[@]:1}"); done
  if ! out="$("$@" 2>&1 >/dev/null)"; then
    err "${label[0]} failed: $out"
    return 1
  fi
}

# Verify a trimmed temp parses as newline-delimited OTLP-JSON. An empty temp (all records aged
# out) is a valid zero-record store. Overridable via CC_OTEL_VERIFY_CMD (test seam).
verify_temp() {
  local temp="$1"
  [[ -s "$temp" ]] || return 0
  if [[ -n "${CC_OTEL_VERIFY_CMD:-}" ]]; then
    "$CC_OTEL_VERIFY_CMD" "$temp"
    return
  fi
  if ! command -v duckdb >/dev/null 2>&1; then
    err "duckdb not found — cannot verify the trimmed store; aborting (original untouched)"
    return 2
  fi
  run_reporting duckdb -c \
    "SELECT count(*) FROM read_json_auto('$(sql_path "$temp")', format='newline_delimited', maximum_object_size=$DUCKDB_MAX_OBJECT_SIZE, sample_size=-1);"
}

# Compact one store file's aged-out (dropped) lines to a cold Parquet file BEFORE the hot trim
# drops them. Cold layout: <store>/cold/<base>-<UTC-ISO-basic>Z.parquet — one file per prune
# run (append-only: a failed compaction can never corrupt prior cold history; the .tmp suffix
# below never matches the *-*.parquet glob the cc_*_cold macros read).
#
# Logs cross the B1 content boundary here: api_request_body/api_response_body rows are
# excluded entirely; user_prompt rows survive (prompt frequency/timing analytics) but body is
# NULLed and the prompt-bearing `prompt` and `prompt_text` attributes are scrubbed from the
# attribute list — unless CC_OTEL_COLD_KEEP_USER_PROMPTS=1. Metrics compact without exclusions. Join-key
# columns (session_id, prompt_id, tool_use_id, trace_id, span_id) ride the shared
# cc_logs_from projection (cc-otel.sql), bridging cold rows to on-disk transcript lookups.
#
# Verify-before-replace extends to the cold step: COPY to a .tmp, verify it parses via
# read_parquet, then mv into place. Any failure returns 1 and the caller aborts the trim with
# the hot store untouched (always-abort — never trim what wasn't compacted). A crash BETWEEN
# the cold mv and the hot mv re-compacts the same lines next run: duplicate cold rows, never
# lost ones.
compact_dropped() {
  local f="$1" dropped="$2" store_dir="$3" cold_ts="$4"
  local base="${f%.json}"
  local cold_dir="$store_dir/cold"
  local cold_file="$cold_dir/$base-$cold_ts.parquet"
  mkdir -p "$cold_dir"
  # Uniquify: a second prune of the same file within the same UTC second must
  # not mv -f over an existing cold file (append-only contract — compacted
  # history is never overwritten). A serial existence check suffices: the
  # prune sentinel already prevents concurrent prunes. The -N suffix still
  # matches the <base>-*.parquet glob the cc_*_cold macros read.
  local n=2
  while [[ -e "$cold_file" ]]; do
    cold_file="$cold_dir/$base-$cold_ts-$n.parquet"
    n=$((n + 1))
  done
  local cold_tmp="$cold_file.tmp"
  if [[ -n "${CC_OTEL_COMPACT_CMD:-}" ]]; then
    if ! "$CC_OTEL_COMPACT_CMD" "$dropped" "$cold_tmp"; then
      rm -f "$cold_tmp"
      return 1
    fi
  else
    if ! command -v duckdb >/dev/null 2>&1; then
      err "duckdb not found — cannot compact aged records to cold; aborting (hot store untouched)"
      return 1
    fi
    local src_sql dst_sql select_sql
    src_sql="$(sql_path "$dropped")"
    dst_sql="$(sql_path "$cold_tmp")"
    if [[ "$base" == cc-logs ]]; then
      if [[ "${CC_OTEL_COLD_KEEP_USER_PROMPTS:-0}" == "1" ]]; then
        select_sql="SELECT * EXCLUDE (attributes_list), to_json(attributes_list) AS log_attributes_raw FROM cc_logs_from('$src_sql')"
      else
        select_sql="SELECT * EXCLUDE (attributes_list) REPLACE (CASE WHEN event_name = 'user_prompt' THEN NULL ELSE body END AS body), to_json(list_filter(attributes_list, lambda x: x.key NOT IN ($COLD_LOG_PROMPT_KEYS))) AS log_attributes_raw FROM cc_logs_from('$src_sql')"
      fi
      # COALESCE: NOT IN over a NULL event_name yields NULL (row silently filtered) — keep
      # nameless rows instead of losing them to three-valued logic.
      select_sql="$select_sql WHERE COALESCE(event_name, '') NOT IN ('api_request_body', 'api_response_body')"
    elif [[ "$base" == cc-traces ]]; then
      if [[ "${CC_OTEL_COLD_KEEP_USER_PROMPTS:-0}" == "1" ]]; then
        select_sql="SELECT * EXCLUDE (attributes_list), to_json(attributes_list) AS span_attributes_raw FROM cc_spans_from('$src_sql')"
      else
        select_sql="SELECT * EXCLUDE (attributes_list) REPLACE (NULL AS user_prompt), to_json(list_filter(attributes_list, lambda x: x.key NOT IN ($COLD_SPAN_PROMPT_KEYS))) AS span_attributes_raw FROM cc_spans_from('$src_sql')"
      fi
    else
      select_sql="SELECT * EXCLUDE (attributes_list), to_json(attributes_list) AS metric_attributes_raw FROM cc_metrics_from('$src_sql')"
    fi
    # -init loads the cc_*_from table macros (SSOT projection). Only the macros are needed
    # here, but the same file also creates the HOT views, which bind their
    # store file eagerly at CREATE — against the real store that re-infers the full multi-MB
    # schema per COPY invocation. Pointing CC_OTEL_STORE at a dir with no store files makes
    # those binds fail instantly; cc-otel.sql's `.bail off` keeps the load going (macros
    # still defined), so compaction works on any store shape — including a store missing one
    # of the two files, and the very first compaction (empty cold/).
    if ! run_reporting env CC_OTEL_STORE="$store_dir/.prune-in-progress" \
      duckdb -init "$(sql_path "$SCRIPT_DIR/cc-otel.sql")" \
      -c "COPY ($select_sql) TO '$dst_sql' (FORMAT PARQUET, COMPRESSION ZSTD);"; then
      rm -f "$cold_tmp"
      return 1
    fi
    if ! run_reporting duckdb -c "SELECT count(*) FROM read_parquet('$dst_sql');"; then
      rm -f "$cold_tmp"
      return 1
    fi
  fi
  # Whatever produced the cold temp (duckdb or seam), it must exist before the promote.
  if [[ ! -f "$cold_tmp" ]]; then
    return 1
  fi
  mv -f "$cold_tmp" "$cold_file"
}

# Cold files compacted before a key joined the scrub lists (or with the keep knob on) still
# hold prompt content. A row is dirty when its attribute list carries a scrubbed key or its
# prompt column (logs: user_prompt body; spans: user_prompt) is non-NULL. Arg: cc-logs|cc-traces.
cold_dirty_predicate() {
  if [[ "$1" == cc-logs ]]; then
    printf '%s' "COALESCE(list_has_any(json_extract_string(log_attributes_raw, '\$[*].key'), [$COLD_LOG_PROMPT_KEYS]), false) OR (event_name = 'user_prompt' AND body IS NOT NULL)"
  else
    printf '%s' "COALESCE(list_has_any(json_extract_string(span_attributes_raw, '\$[*].key'), [$COLD_SPAN_PROMPT_KEYS]), false) OR user_prompt IS NOT NULL"
  fi
}

# The compaction scrub, re-applied to an existing cold file (SQL-literal path). Every other
# column passes through unchanged; NULLIF(x, x) NULLs a column without changing its type.
cold_scrub_select() {
  local kind="$1" src_sql="$2"
  if [[ "$kind" == cc-logs ]]; then
    printf '%s' "SELECT * REPLACE (CASE WHEN event_name = 'user_prompt' THEN NULLIF(body, body) ELSE body END AS body, to_json(list_filter(from_json(log_attributes_raw, '$COLD_ATTR_SHAPE'), lambda x: x.key NOT IN ($COLD_LOG_PROMPT_KEYS))) AS log_attributes_raw) FROM read_parquet('$src_sql')"
  else
    printf '%s' "SELECT * REPLACE (NULLIF(user_prompt, user_prompt) AS user_prompt, to_json(list_filter(from_json(span_attributes_raw, '$COLD_ATTR_SHAPE'), lambda x: x.key NOT IN ($COLD_SPAN_PROMPT_KEYS))) AS span_attributes_raw) FROM read_parquet('$src_sql')"
  fi
}

# Print "<rows>,<dirty rows>" for one cold Parquet file.
cold_counts() {
  local kind="$1" file="$2" out
  out="$(duckdb -csv -noheader -c "SELECT count(*), count(*) FILTER (WHERE $(cold_dirty_predicate "$kind")) FROM read_parquet('$(sql_path "$file")');" 2>&1)" || {
    err "duckdb could not read $file: $out"
    return 1
  }
  printf '%s\n' "${out//$'\r'/}"
}

# One-line notice when cold files still hold prompt content. Detection only, best-effort:
# silent with the keep knob on, without duckdb, or when a count fails.
cold_prompt_notice() {
  local store_dir="$1" kind file counts dirty_files=0
  [[ "${CC_OTEL_COLD_KEEP_USER_PROMPTS:-0}" == "1" ]] && return 0
  command -v duckdb >/dev/null 2>&1 || return 0
  for kind in cc-logs cc-traces; do
    for file in "$store_dir/cold/$kind"-*.parquet; do
      [[ -f "$file" ]] || continue
      counts="$(cold_counts "$kind" "$file" 2>/dev/null)" || continue
      [[ "${counts#*,}" == 0 ]] || dirty_files=$((dirty_files + 1))
    done
  done
  if ((dirty_files > 0)); then
    printf 'notice: %s cold file(s) still hold prompt content; run prune-otel-store.sh --scrub-cold\n' "$dirty_files"
  fi
}

# Rewrite each dirty cold logs/spans file with the compaction scrub: COPY to a .tmp in cold/,
# verify the row count is unchanged and no dirty row remains, then mv over the original.
# Clean files are left untouched. dry_run=true reports only. Returns 1 on the first failure,
# leaving that file and every later one as they were.
scrub_cold() {
  local store_dir="$1" dry_run="$2"
  local kind file name counts rows dirty tmp after affected=0 scrubbed=0
  for kind in cc-logs cc-traces; do
    for file in "$store_dir/cold/$kind"-*.parquet; do
      [[ -f "$file" ]] || continue
      name="cold/${file##*/}"
      counts="$(cold_counts "$kind" "$file")" || return 1
      rows="${counts%,*}"
      dirty="${counts#*,}"
      if [[ "$dirty" == 0 ]]; then
        printf '%s: clean rows=%s\n' "$name" "$rows"
        continue
      fi
      affected=$((affected + 1))
      if [[ "$dry_run" == true ]]; then
        printf '%s: would_scrub rows=%s prompt_rows=%s\n' "$name" "$rows" "$dirty"
        continue
      fi
      tmp="$file.scrub.tmp"
      if ! run_reporting duckdb -c "COPY ($(cold_scrub_select "$kind" "$(sql_path "$file")")) TO '$(sql_path "$tmp")' (FORMAT PARQUET, COMPRESSION ZSTD);"; then
        rm -f "$tmp"
        return 1
      fi
      after="$(cold_counts "$kind" "$tmp")" || {
        rm -f "$tmp"
        return 1
      }
      if [[ "$after" != "$rows,0" ]]; then
        rm -f "$tmp"
        err "scrub verification failed for $name: expected $rows,0 got $after (original untouched)"
        return 1
      fi
      mv -f "$tmp" "$file"
      scrubbed=$((scrubbed + 1))
      printf '%s: scrubbed rows=%s prompt_rows=%s\n' "$name" "$rows" "$dirty"
    done
  done
  if [[ "$dry_run" == true ]]; then
    printf 'action=dry-run-scrub-cold affected_files=%s\n' "$affected"
  else
    printf 'action=scrubbed-cold scrubbed_files=%s\n' "$scrubbed"
  fi
}

# Strip api_*_body logRecords from each surgery-routed line (records past the body window
# whose batch line is still inside the structure window). Lines left with ZERO records (pure-
# body batches) drop entirely; survivors are re-serialized by jq and APPENDED to the kept
# temp (sibling structure records preserved). Stripped body records do NOT reach cold — the
# B1 boundary excludes api_*_body rows there anyway. Prints
# "surgery_kept=<n> surgery_dropped=<n>"; returns 1 on jq absence or failure (caller aborts
# BEFORE the hot trim — always-abort, original untouched).
SURGERY_JQ_FILTER='
  .resourceLogs[]?.scopeLogs[]?.logRecords |= map(select(
    [.attributes[]? | select(.key == "event.name") | .value.stringValue // ""]
    | any(. == "api_request_body" or . == "api_response_body") | not
  ))
  | select([.resourceLogs[]?.scopeLogs[]?.logRecords[]?] | length > 0)
'
readonly SURGERY_JQ_FILTER
surgery_file() {
  local surgery_src="$1" kept_dst="$2"
  local out_tmp="$surgery_src.out.tmp"
  if ! command -v jq >/dev/null 2>&1; then
    err "jq not found — cannot strip aged body records; aborting (original untouched)"
    return 1
  fi
  local jq_err
  if ! jq_err="$(jq -c "$SURGERY_JQ_FILTER" "$surgery_src" 2>&1 >"$out_tmp")"; then
    err "jq failed: $jq_err"
    rm -f "$out_tmp"
    return 1
  fi
  local in_lines out_lines
  in_lines="$(wc -l <"$surgery_src" | tr -d ' \r')"
  out_lines="$(wc -l <"$out_tmp" | tr -d ' \r')"
  cat "$out_tmp" >>"$kept_dst"
  rm -f "$out_tmp"
  printf 'surgery_kept=%s surgery_dropped=%s\n' "$out_lines" "$((in_lines - out_lines))"
}
