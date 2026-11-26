#!/usr/bin/env bash
# Requires SCRIPT_DIR, OS_KIND, and err() from the caller.
# shellcheck disable=SC2154  # SCRIPT_DIR and OS_KIND are set by prune-otel-store.sh before source.

readonly DUCKDB_MAX_OBJECT_SIZE=33554432

readonly COLD_LOG_PROMPT_KEYS="'prompt', 'prompt_text'"
readonly COLD_SPAN_PROMPT_KEYS="'user_prompt', 'prompt', 'prompt_text'"
readonly COLD_LOG_CONTENT_COLS="response error tool_parameters tool_input hook_definitions hook_matcher managed_settings_settings managed_settings_helper_path body_ref workspace_host_paths user_email"
readonly COLD_LOG_CONTENT_KEYS="'response', 'error', 'tool_parameters', 'tool_input', 'hook_definitions', 'hook_matcher', 'managed_settings.settings', 'managed_settings.helper.path', 'body_ref', 'workspace.host_paths', 'user.email'"
readonly COLD_SPAN_CONTENT_COLS="user_system_prompt response_model_output new_context tool_input full_command error hook_definitions system_prompt_preview user_email file_path content output diff bash_command"
readonly COLD_SPAN_CONTENT_KEYS="'user_system_prompt', 'response.model_output', 'new_context', 'tool_input', 'full_command', 'error', 'hook_definitions', 'system_prompt_preview', 'user.email', 'file_path'"
readonly COLD_METRIC_CONTENT_COLS="user_email"
readonly COLD_METRIC_CONTENT_KEYS="'user.email'"
readonly COLD_ATTR_SHAPE='[{"key":"VARCHAR","value":"JSON"}]'

keep_prompts() { [[ "${CC_OTEL_COLD_KEEP_USER_PROMPTS:-0}" == "1" ]]; }
scrub_content() { [[ "${CC_OTEL_COLD_KEEP_CONTENT:-1}" == "0" ]]; }

cold_raw_col() { case "$1" in cc-logs) printf log_attributes_raw ;; cc-traces) printf span_attributes_raw ;; *) printf metric_attributes_raw ;; esac }
cold_from_macro() { case "$1" in cc-logs) printf cc_logs_from ;; cc-traces) printf cc_spans_from ;; *) printf cc_metrics_from ;; esac }
cold_stub_macro() { case "$1" in cc-logs) printf cc_logs_cold_stub ;; cc-traces) printf cc_spans_cold_stub ;; *) printf cc_metrics_cold_stub ;; esac }
cold_content_cols() { case "$1" in cc-logs) printf '%s' "$COLD_LOG_CONTENT_COLS" ;; cc-traces) printf '%s' "$COLD_SPAN_CONTENT_COLS" ;; *) printf '%s' "$COLD_METRIC_CONTENT_COLS" ;; esac }
cold_content_keys() { case "$1" in cc-logs) printf '%s' "$COLD_LOG_CONTENT_KEYS" ;; cc-traces) printf '%s' "$COLD_SPAN_CONTENT_KEYS" ;; *) printf '%s' "$COLD_METRIC_CONTENT_KEYS" ;; esac }

cold_scrub_keys() {
  local kind="$1" keys=""
  if ! keep_prompts; then
    case "$kind" in cc-logs) keys="$COLD_LOG_PROMPT_KEYS" ;; cc-traces) keys="$COLD_SPAN_PROMPT_KEYS" ;; *) ;; esac
  fi
  if scrub_content; then keys="${keys:+$keys, }$(cold_content_keys "$kind")"; fi
  printf '%s' "$keys"
}

cold_scrub_replace() {
  local kind="$1" items="" c
  if ! keep_prompts; then
    case "$kind" in
      cc-logs) items="CASE WHEN event_name = 'user_prompt' THEN NULLIF(body, body) ELSE body END AS body, NULLIF(prompt, prompt) AS prompt" ;;
      cc-traces) items="NULLIF(user_prompt, user_prompt) AS user_prompt" ;;
      *) ;;
    esac
  fi
  if scrub_content; then
    for c in $(cold_content_cols "$kind"); do items="${items:+$items, }NULLIF($c, $c) AS $c"; done
  fi
  printf '%s' "$items"
}

duckdb_cold() {
  local cold_dir="$1"
  shift
  env CC_OTEL_STORE="$cold_dir" duckdb -init "$(sql_path "$SCRIPT_DIR/cc-otel.sql")" -cmd ".bail on" "$@"
}

cold_rows_sql() {
  printf "(SELECT * FROM %s() UNION ALL BY NAME SELECT * FROM read_parquet('%s', union_by_name = true%s))" \
    "$(cold_stub_macro "$1")" "$2" "${3:-}"
}

sql_path() {
  local p="$1"
  if [[ "$OS_KIND" == windows ]] && command -v cygpath >/dev/null 2>&1; then
    p="$(cygpath -m "$p")"
  fi
  printf '%s\n' "${p//\'/\'\'}"
}

run_reporting() {
  local out label=("$@")
  [[ "${label[0]}" == env ]] && label=("${label[@]:1}")
  while [[ "${label[0]}" == *=* ]]; do label=("${label[@]:1}"); done
  if ! out="$("$@" 2>&1 >/dev/null)"; then
    err "${label[0]} failed: $out"
    return 1
  fi
}

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

compact_dropped() {
  local f="$1" dropped="$2" store_dir="$3" cold_ts="$4"
  local base="${f%.json}"
  local cold_dir="$store_dir/cold"
  local cold_file="$cold_dir/$base-$cold_ts.parquet"
  mkdir -p "$cold_dir"
  local n=2
  while [[ -e "$cold_file" ]]; do
    cold_file="$cold_dir/$base-$cold_ts-$n.parquet"
    n=$((n + 1))
  done
  local cold_tmp="$cold_file.tmp"
  if keep_prompts && [[ "$base" != cc-metrics ]]; then
    rm -f "$cold_dir/$COLD_CLEAN_MARKER"
  fi
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
    local src_sql dst_sql select_sql keys replace attrs
    src_sql="$(sql_path "$dropped")"
    dst_sql="$(sql_path "$cold_tmp")"
    keys="$(cold_scrub_keys "$base")"
    replace="$(cold_scrub_replace "$base")"
    attrs="attributes_list"
    [[ -n "$keys" ]] && attrs="list_filter(attributes_list, lambda x: x.key NOT IN ($keys))"
    select_sql="SELECT * EXCLUDE (attributes_list)${replace:+ REPLACE ($replace)}, to_json($attrs) AS $(cold_raw_col "$base") FROM $(cold_from_macro "$base")('$src_sql')"
    if [[ "$base" == cc-logs ]]; then
      select_sql="$select_sql WHERE COALESCE(event_name, '') NOT IN ('api_request_body', 'api_response_body')"
    fi
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
  if [[ ! -f "$cold_tmp" ]]; then
    return 1
  fi
  mv -f "$cold_tmp" "$cold_file"
}

cold_dirty_predicate() {
  local kind="$1" scope="$2" raw keys="" cols="" c pred=""
  raw="$(cold_raw_col "$kind")"
  if [[ "$scope" == prompts ]] || ! keep_prompts; then
    case "$kind" in
      cc-logs) keys="$COLD_LOG_PROMPT_KEYS" pred="(event_name = 'user_prompt' AND body IS NOT NULL) OR prompt IS NOT NULL" ;;
      cc-traces) keys="$COLD_SPAN_PROMPT_KEYS" pred="user_prompt IS NOT NULL" ;;
      *) ;;
    esac
  fi
  if [[ "$scope" == all ]] && scrub_content; then
    keys="${keys:+$keys, }$(cold_content_keys "$kind")"
    cols="$(cold_content_cols "$kind")"
  fi
  [[ -n "$keys" ]] || {
    printf 'false'
    return
  }
  for c in $cols; do pred="${pred:+$pred OR }$c IS NOT NULL"; done
  printf '%s' "COALESCE(list_has_any(json_extract_string($raw, '\$[*].key'), [$keys]), false)${pred:+ OR $pred}"
}

cold_scrub_select() {
  local kind="$1" src_sql="$2" raw keys replace
  raw="$(cold_raw_col "$kind")"
  keys="$(cold_scrub_keys "$kind")"
  replace="$(cold_scrub_replace "$kind")"
  printf '%s' "SELECT * REPLACE (${replace:+$replace, }to_json(list_filter(from_json($raw, '$COLD_ATTR_SHAPE'), lambda x: x.key NOT IN (${keys:-''}))) AS $raw) FROM $(cold_rows_sql "$kind" "$src_sql")"
}

duckdb_cold_read() {
  local what="$1" out errf
  shift
  errf="$(mktemp)"
  out="$(duckdb_cold "$@" 2>"$errf" </dev/null)" || {
    err "duckdb could not read $what: $(tail -n 1 "$errf")"
    rm -f "$errf"
    return 1
  }
  rm -f "$errf"
  printf '%s\n' "${out//$'\r'/}"
}

cold_counts() {
  local kind="$1" file="$2"
  duckdb_cold_read "$file" "${file%/*}" -csv -noheader -c "SELECT count(*), count(*) FILTER (WHERE $(cold_dirty_predicate "$kind" all)) FROM $(cold_rows_sql "$kind" "$(sql_path "$file")");"
}

cold_glob_counts() {
  local kind="$1" cold_dir="$2" scope="$3"
  compgen -G "$cold_dir/$kind-*.parquet" >/dev/null || return 0
  duckdb_cold_read "$cold_dir/$kind-*.parquet" "$cold_dir" -list -noheader -c "SELECT count(*), count(*) FILTER (WHERE $(cold_dirty_predicate "$kind" "$scope")), parse_filename(filename) FROM $(cold_rows_sql "$kind" "$(sql_path "$cold_dir")/$kind-*.parquet" ", filename = true") GROUP BY filename ORDER BY filename;"
}

cold_dirty_file_count() {
  local cold_dir="$1" kind counts rows dirty name n=0
  for kind in cc-logs cc-traces; do
    counts="$(cold_glob_counts "$kind" "$cold_dir" prompts)" || return 1
    while IFS='|' read -r rows dirty name; do
      [[ -n "$name" && "$dirty" != 0 ]] && n=$((n + 1))
    done <<<"$counts"
  done
  printf '%s\n' "$n"
}

cold_snapshot() {
  {
    compgen -G "$1/cc-logs-*.parquet" || true
    compgen -G "$1/cc-traces-*.parquet" || true
  } | sort | cksum
}

readonly COLD_CLEAN_MARKER=.prompt-scrub-clean
COLD_CLEAN_SNAPSHOT=""

cold_prompt_notice() {
  local cold_dir="$1/cold" snapshot dirty_files
  COLD_CLEAN_SNAPSHOT=""
  keep_prompts && return 0
  [[ -e "$cold_dir/$COLD_CLEAN_MARKER" ]] && return 0
  command -v duckdb >/dev/null 2>&1 || return 0
  snapshot="$(cold_snapshot "$cold_dir")"
  dirty_files="$(cold_dirty_file_count "$cold_dir" 2>/dev/null)" || return 0
  if ((dirty_files > 0)); then
    printf 'notice: %s cold file(s) still hold prompt content; run prune-otel-store.sh --scrub-cold\n' "$dirty_files"
  else
    COLD_CLEAN_SNAPSHOT="$snapshot"
  fi
}

mark_cold_clean() {
  local cold_dir="$1/cold"
  [[ -n "$COLD_CLEAN_SNAPSHOT" ]] || return 0
  [[ "$(cold_snapshot "$cold_dir")" == "$COLD_CLEAN_SNAPSHOT" ]] || return 0
  mkdir -p "$cold_dir"
  : >"$cold_dir/$COLD_CLEAN_MARKER"
}

mark_cold_clean_briefly() {
  local store_dir="$1"
  [[ -n "$COLD_CLEAN_SNAPSHOT" && -d "$store_dir/cold" ]] || return 0
  # shellcheck disable=SC2310  # failure IS the handled branch; set -e suppression is intended
  take_sentinel || return 0
  mark_cold_clean "$store_dir" || true
  release_sentinel
}

scrub_cold() {
  local store_dir="$1" dry_run="$2"
  local cold_dir="$1/cold" kind file name counts rows dirty base tmp after affected=0 scrubbed=0
  local kinds=(cc-logs cc-traces)
  scrub_content && kinds+=(cc-metrics)
  for kind in "${kinds[@]}"; do
    counts="$(cold_glob_counts "$kind" "$cold_dir" all)" || return 1
    while IFS='|' read -r rows dirty base; do
      [[ -n "$base" ]] || continue
      file="$cold_dir/$base"
      name="cold/$base"
      if [[ "$dirty" == 0 ]]; then
        printf '%s: clean rows=%s\n' "$name" "$rows"
        continue
      fi
      affected=$((affected + 1))
      if [[ "$dry_run" == true ]]; then
        printf '%s: would_scrub rows=%s scrub_rows=%s\n' "$name" "$rows" "$dirty"
        continue
      fi
      tmp="$file.scrub.tmp"
      if ! run_reporting duckdb_cold "$cold_dir" -c "COPY ($(cold_scrub_select "$kind" "$(sql_path "$file")")) TO '$(sql_path "$tmp")' (FORMAT PARQUET, COMPRESSION ZSTD);" </dev/null; then
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
      printf '%s: scrubbed rows=%s scrub_rows=%s\n' "$name" "$rows" "$dirty"
    done <<<"$counts"
  done
  if [[ "$dry_run" == true ]]; then
    printf 'action=dry-run-scrub-cold affected_files=%s\n' "$affected"
  else
    if ! keep_prompts; then
      mkdir -p "$cold_dir"
      : >"$cold_dir/$COLD_CLEAN_MARKER"
    fi
    printf 'action=scrubbed-cold scrubbed_files=%s\n' "$scrubbed"
  fi
}

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
