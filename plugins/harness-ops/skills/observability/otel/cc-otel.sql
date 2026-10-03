-- cc-otel.sql — DuckDB init for querying the local Claude Code OTEL store.
--
-- Usage: the view paths resolve via ${CC_OTEL_STORE} (the absolute store dir set by
-- machine provisioning), so queries work from ANY worktree.
-- When CC_OTEL_STORE is unset the views fall back to the repo-root-relative path, so a
-- manual run must be FROM THE REPO ROOT:
--   duckdb -init ${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/cc-otel.sql
--     → interactive session with the cc_logs / cc_metrics / cc_spans hot views, the cc_traces
--       aggregate view, and the cc_*_cold() cold table macros ready.
--   duckdb -init ${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/cc-otel.sql -c "SELECT count(*) FROM cc_logs;"
--     → one-shot query.
--
-- Two tiers share one projection definition (SSOT): the cc_logs_from / cc_metrics_from /
-- cc_spans_from table macros below are the single source of the unnest + column contract,
-- consumed by
--   1. the HOT views (cc_logs / cc_metrics / cc_spans) and cc_traces aggregate over live NDJSON,
--   2. prune-otel-store.sh's cold compaction COPY (aged lines -> cold/*.parquet),
--   3. the COLD table macros (cc_*_cold()) read the Parquet those COPYs wrote,
--      so hot and cold expose the SAME column contract and UNION ALL cleanly.
--
-- Read path (hot): native DuckDB read_json_auto over the raw newline-delimited OTLP/JSON the
-- Collector's file exporter writes (format='newline_delimited'). The store is unnested by hand:
-- resourceLogs → scopeLogs → logRecords (logs); resourceMetrics → scopeMetrics → metrics
-- → sum.dataPoints (metrics); resourceSpans → scopeSpans → spans (traces). Attributes are
-- an array of {key, value} structs,
-- where value is a typed union ({stringValue} | {intValue, as quoted string} | {doubleValue}
-- | {boolValue} | {arrayValue}).
--
-- Promoted columns: every attribute the monitoring page documents for a signal is a typed
-- column, read from ONE key -> value map per record (cc_attr_map) instead of a list scan per
-- column. Each value is kept as JSON and read through json_extract_string, because
-- read_json_auto infers only the value sub-keys present in a file: a native .doubleValue
-- reference binder-errors on a store that never sent one. Spans also fold in the attributes
-- of their tool.output span event (content, output, diff, bash_command). An attribute a
-- record does not carry reads NULL; the *_attributes_raw column keeps every attribute,
-- documented or not. Pointer: https://code.claude.com/docs/en/monitoring-usage#available-metrics-and-events
-- and #span-attributes. As of 2026-10-02. Recheck trigger: the page adds, renames or retypes
-- an attribute; add the column to the projection and to its cold stub together.
--
-- The macros surface the attribute array as an internal attributes_list column (typed LIST,
-- last position); each consumer serializes it (to_json -> *_attributes_raw) or scrubs it
-- (cold compaction's privacy boundary) as its final step.
--
-- sample_size=-1 forces full-file schema inference so the value-union and the re-serialized
-- *_attributes_raw columns are faithful (a partial sample can drop a value sub-key seen only
-- in later records). maximum_object_size is set to 32 MB — generous headroom over the ~224 KB
-- largest record (raw API bodies are captured inline) so a single line never overflows.
--
-- event_time: read_json yields timeUnixNano as raw NANOSECONDS (a 19-digit value, quoted in
-- OTLP/JSON). Integer-divide by 1000 to microseconds, then make_timestamp() (which takes
-- microseconds-since-epoch) renders the correct UTC time. No unit fudge — this is the wire
-- value, not an extension's reinterpretation.
--
-- Error posture when a source is absent: DuckDB binds CREATE VIEW eagerly, so a HOT view
-- whose store file does not exist yet (a fresh machine whose Collector has never run, or a
-- store with only one of the two files) fails at CREATE time. `.bail off` below makes that
-- non-fatal: the failing view prints its error and is skipped, the rest of this file still
-- loads (after the machine Collector receives a CC session, re-run the init). The COLD
-- surfaces are zero-arg-callable TABLE MACROS (not views)
-- so they cannot even hit that bind: cold/*.parquet is an EMPTY glob until the first
-- aged-out prune run compacts something, and a macro with a defaulted src parameter defers
-- binding to query time — cc_logs_cold() / cc_metrics_cold() error lazily ("No files
-- found") until the first compaction writes a file. Either way the fix is the same:
-- produce the data, then query.
--
-- `.bail off` is a duckdb CLI dot command (this file is a CLI init file, its only consumer);
-- the CLI default for init files is bail-on-first-error, which would otherwise abort the
-- whole load — including prune-otel-store.sh's `duckdb -init` compaction invocation, which
-- only needs the macros below and deliberately points CC_OTEL_STORE at a dir with no store files so the
-- hot-view binds fail fast instead of re-inferring the full store schema per COPY.
.bail off

-- Attribute map: key -> value JSON. map_from_entries rejects a duplicate key, so a record that
-- repeats one keeps its first occurrence (as the list scan this replaces did); the dedupe is
-- quadratic, so it runs only on such a record.
CREATE OR REPLACE MACRO cc_attr_entries(attrs) AS list_transform(attrs, lambda e: {'key': e.key, 'value': to_json(e.value)});
CREATE OR REPLACE MACRO cc_attr_map(entries) AS map_from_entries(
  CASE WHEN len(list_distinct(list_transform(entries, lambda y: y.key))) = len(entries) THEN entries
       ELSE list_filter(entries, lambda x, i: list_position(list_transform(entries, lambda y: y.key), x.key) = i) END);
-- Scalar read: whichever value sub-key the attribute arrived in, as VARCHAR.
CREATE OR REPLACE MACRO cc_attr(a, k) AS COALESCE(
  json_extract_string(a[k], '$.stringValue'), json_extract_string(a[k], '$.intValue'),
  json_extract_string(a[k], '$.doubleValue'), json_extract_string(a[k], '$.boolValue'));
CREATE OR REPLACE MACRO cc_attr_bigint(a, k) AS
  COALESCE(TRY_CAST(cc_attr(a, k) AS BIGINT), TRY_CAST(TRY_CAST(cc_attr(a, k) AS DOUBLE) AS BIGINT));
CREATE OR REPLACE MACRO cc_attr_double(a, k) AS TRY_CAST(cc_attr(a, k) AS DOUBLE);
CREATE OR REPLACE MACRO cc_attr_bool(a, k) AS TRY_CAST(cc_attr(a, k) AS BOOLEAN);
CREATE OR REPLACE MACRO cc_attr_list(a, k) AS json_extract_string(a[k], '$.arrayValue.values[*].stringValue');

-- Logs projection (SSOT): one typed row per Claude Code event. Columns are NULL where the
-- event type does not emit that attribute; the full array rides along as attributes_list
-- (last column) for the consumer to serialize or scrub.
CREATE OR REPLACE MACRO cc_logs_from(src) AS TABLE
WITH resource_logs AS (
  SELECT unnest(resourceLogs) AS rl
  FROM read_json_auto(src, format = 'newline_delimited', maximum_object_size = 33554432, sample_size = -1)
),
scope_logs AS (
  SELECT unnest(rl.scopeLogs) AS sl FROM resource_logs
),
records AS (
  SELECT unnest(sl.logRecords) AS r FROM scope_logs
),
attrs AS (
  SELECT r, cc_attr_map(cc_attr_entries(r.attributes)) AS a FROM records
)
SELECT
  make_timestamp(TRY_CAST(r.timeUnixNano AS BIGINT) // 1000)    AS event_time,
  cc_attr(a, 'session.id')                                       AS session_id,
  cc_attr(a, 'event.name')                                       AS event_name,
  cc_attr(a, 'tool_name')                                        AS tool_name,
  cc_attr(a, 'hook_name')                                        AS hook_name,
  cc_attr(a, 'decision')                                         AS decision,
  cc_attr_double(a, 'duration_ms')                               AS duration_ms,
  cc_attr(a, 'success')                                          AS success,
  -- tool_decision emits `source` (official); tool_result emits `decision_source` — one column.
  COALESCE(cc_attr(a, 'source'), cc_attr(a, 'decision_source'))  AS source,
  cc_attr(a, 'prompt.id')                                        AS prompt_id,
  cc_attr(a, 'tool_use_id')                                      AS tool_use_id,
  cc_attr(a, 'terminal.type')                                    AS terminal_type,
  cc_attr_bigint(a, 'event.sequence')                            AS event_sequence,
  -- traceId/spanId via a by-name struct cast, NOT native r.traceId: read_json_auto infers only
  -- the keys present, and records emitted without tracing carry neither, so such a slice (a
  -- prune's dropped temp, or a whole store) binder-errors on a native reference. The cast
  -- yields NULL for an absent member and, unlike to_json(r), never serializes the body.
  -- timeUnixNano is in the target because the cast needs at least one matching member.
  (r::STRUCT(timeUnixNano VARCHAR, traceId VARCHAR, spanId VARCHAR)).traceId AS trace_id,
  (r::STRUCT(timeUnixNano VARCHAR, traceId VARCHAR, spanId VARCHAR)).spanId  AS span_id,
  r.body.stringValue                                             AS body,
  cc_attr(a, 'ccr.session.id')                                   AS ccr_session_id,
  cc_attr(a, 'app.version')                                      AS app_version,
  cc_attr(a, 'app.entrypoint')                                   AS app_entrypoint,
  cc_attr(a, 'organization.id')                                  AS organization_id,
  cc_attr(a, 'user.account_uuid')                                AS user_account_uuid,
  cc_attr(a, 'user.account_id')                                  AS user_account_id,
  cc_attr(a, 'user.id')                                          AS user_id,
  cc_attr(a, 'user.email')                                       AS user_email,
  cc_attr(a, 'user.groups')                                      AS user_groups,
  cc_attr(a, 'identity.source')                                  AS identity_source,
  cc_attr(a, 'vcs.repository.url.full')                          AS vcs_repository_url_full,
  cc_attr(a, 'vcs.owner.name')                                   AS vcs_owner_name,
  cc_attr(a, 'vcs.repository.name')                              AS vcs_repository_name,
  cc_attr(a, 'vcs.provider.name')                                AS vcs_provider_name,
  cc_attr_list(a, 'workspace.host_paths')                        AS workspace_host_paths,
  cc_attr(a, 'workflow.run_id')                                  AS workflow_run_id,
  cc_attr(a, 'workflow.name')                                    AS workflow_name,
  cc_attr(a, 'event.timestamp')                                  AS event_timestamp,
  cc_attr(a, 'message.uuid')                                     AS message_uuid,
  cc_attr(a, 'message.id')                                       AS message_id,
  cc_attr(a, 'request_id')                                       AS request_id,
  cc_attr(a, 'client_request_id')                                AS client_request_id,
  cc_attr(a, 'model')                                            AS model,
  cc_attr(a, 'query_source')                                     AS query_source,
  cc_attr(a, 'speed')                                            AS speed,
  cc_attr(a, 'effort')                                           AS effort,
  cc_attr(a, 'agent.name')                                       AS agent_name,
  cc_attr(a, 'skill.name')                                       AS skill_name,
  cc_attr(a, 'plugin.name')                                      AS plugin_name,
  cc_attr(a, 'marketplace.name')                                 AS marketplace_name,
  cc_attr(a, 'mcp_server.name')                                  AS mcp_server_name,
  cc_attr(a, 'mcp_tool.name')                                    AS mcp_tool_name,
  cc_attr_bigint(a, 'prompt_length')                             AS prompt_length,
  cc_attr(a, 'prompt')                                           AS prompt,
  cc_attr(a, 'command_name')                                     AS command_name,
  cc_attr(a, 'command_source')                                   AS command_source,
  cc_attr_bigint(a, 'response_length')                           AS response_length,
  cc_attr(a, 'response')                                         AS response,
  COALESCE(cc_attr(a, 'error_type'), cc_attr(a, 'error.type')) AS error_type,
  cc_attr(a, 'error')                                            AS error,
  cc_attr(a, 'decision_type')                                    AS decision_type,
  cc_attr_bigint(a, 'tool_input_size_bytes')                     AS tool_input_size_bytes,
  cc_attr_bigint(a, 'tool_result_size_bytes')                    AS tool_result_size_bytes,
  cc_attr(a, 'mcp_server_scope')                                 AS mcp_server_scope,
  cc_attr(a, 'vcs.ref.head.revision')                            AS vcs_ref_head_revision,
  cc_attr(a, 'vcs.ref.head.name')                                AS vcs_ref_head_name,
  cc_attr(a, 'vcs.ref.head.type')                                AS vcs_ref_head_type,
  cc_attr(a, 'tool_parameters')                                  AS tool_parameters,
  cc_attr(a, 'tool_input')                                       AS tool_input,
  cc_attr(a, 'tool_source')                                      AS tool_source,
  cc_attr_double(a, 'cost_usd')                                  AS cost_usd,
  cc_attr_bigint(a, 'cost_usd_micros')                           AS cost_usd_micros,
  cc_attr_bigint(a, 'input_tokens')                              AS input_tokens,
  cc_attr_bigint(a, 'output_tokens')                             AS output_tokens,
  cc_attr_bigint(a, 'cache_read_tokens')                         AS cache_read_tokens,
  cc_attr_bigint(a, 'cache_creation_tokens')                     AS cache_creation_tokens,
  cc_attr_bigint(a, 'status_code')                               AS status_code,
  cc_attr_bigint(a, 'attempt')                                   AS attempt,
  cc_attr_bool(a, 'server_fallback_hop')                         AS server_fallback_hop,
  cc_attr_bool(a, 'has_category')                                AS has_category,
  cc_attr_bool(a, 'has_explanation')                             AS has_explanation,
  cc_attr(a, 'category')                                         AS category,
  cc_attr(a, 'body_ref')                                         AS body_ref,
  cc_attr_bigint(a, 'body_length')                               AS body_length,
  cc_attr_bool(a, 'body_truncated')                              AS body_truncated,
  cc_attr(a, 'request_body_id')                                  AS request_body_id,
  cc_attr(a, 'from_mode')                                        AS from_mode,
  cc_attr(a, 'to_mode')                                          AS to_mode,
  cc_attr(a, 'trigger')                                          AS trigger,
  cc_attr(a, 'action')                                           AS action,
  cc_attr(a, 'auth_method')                                      AS auth_method,
  cc_attr(a, 'error_category')                                   AS error_category,
  cc_attr(a, 'status')                                           AS status,
  cc_attr(a, 'transport_type')                                   AS transport_type,
  cc_attr(a, 'server_scope')                                     AS server_scope,
  cc_attr(a, 'server_name')                                      AS server_name,
  cc_attr(a, 'error_code')                                       AS error_code,
  cc_attr(a, 'error_name')                                       AS error_name,
  cc_attr_bool(a, 'is_plugin')                                   AS is_plugin,
  cc_attr(a, 'plugin_id')                                        AS plugin_id,
  cc_attr(a, 'plugin_id_hash')                                   AS plugin_id_hash,
  cc_attr(a, 'plugin.version')                                   AS plugin_version,
  cc_attr(a, 'plugin.scope')                                     AS plugin_scope,
  cc_attr_bool(a, 'marketplace.is_official')                     AS marketplace_is_official,
  cc_attr(a, 'install.trigger')                                  AS install_trigger,
  cc_attr(a, 'enabled_via')                                      AS enabled_via,
  cc_attr_bool(a, 'has_hooks')                                   AS has_hooks,
  cc_attr_bool(a, 'has_mcp')                                     AS has_mcp,
  cc_attr_bool(a, 'host_owned_mcp')                              AS host_owned_mcp,
  cc_attr_bigint(a, 'skill_path_count')                          AS skill_path_count,
  cc_attr_bigint(a, 'command_path_count')                        AS command_path_count,
  cc_attr_bigint(a, 'agent_path_count')                          AS agent_path_count,
  cc_attr_bool(a, 'safe_mode')                                   AS safe_mode,
  cc_attr(a, 'invocation_trigger')                               AS invocation_trigger,
  cc_attr(a, 'skill.source')                                     AS skill_source,
  cc_attr(a, 'skill.kind')                                       AS skill_kind,
  cc_attr(a, 'mention_type')                                     AS mention_type,
  cc_attr_bigint(a, 'total_attempts')                            AS total_attempts,
  cc_attr_double(a, 'total_retry_duration_ms')                   AS total_retry_duration_ms,
  cc_attr(a, 'hook_event')                                       AS hook_event,
  cc_attr(a, 'hook_type')                                        AS hook_type,
  cc_attr(a, 'hook_source')                                      AS hook_source,
  cc_attr(a, 'hook_matcher')                                     AS hook_matcher,
  cc_attr(a, 'hook_definitions')                                 AS hook_definitions,
  cc_attr_bool(a, 'managed_only')                                AS managed_only,
  cc_attr_bigint(a, 'num_hooks')                                 AS num_hooks,
  cc_attr_bigint(a, 'num_success')                               AS num_success,
  cc_attr_bigint(a, 'num_blocking')                              AS num_blocking,
  cc_attr_bigint(a, 'num_non_blocking_error')                    AS num_non_blocking_error,
  cc_attr_bigint(a, 'num_cancelled')                             AS num_cancelled,
  cc_attr_double(a, 'total_duration_ms')                         AS total_duration_ms,
  cc_attr_bigint(a, 'stdout_chars')                              AS stdout_chars,
  cc_attr_bigint(a, 'additional_context_chars')                  AS additional_context_chars,
  cc_attr_bigint(a, 'system_message_chars')                      AS system_message_chars,
  cc_attr_bigint(a, 'initial_user_message_chars')                AS initial_user_message_chars,
  cc_attr_bigint(a, 'num_outputs_persisted')                     AS num_outputs_persisted,
  cc_attr_bigint(a, 'pre_tokens')                                AS pre_tokens,
  cc_attr_bigint(a, 'post_tokens')                               AS post_tokens,
  cc_attr(a, 'precompute_reuse')                                 AS precompute_reuse,
  cc_attr(a, 'agent_type')                                       AS agent_type,
  cc_attr(a, 'agent.source')                                     AS agent_source,
  cc_attr_bool(a, 'is_built_in')                                 AS is_built_in,
  cc_attr_bool(a, 'is_async')                                    AS is_async,
  cc_attr_bigint(a, 'total_tokens')                              AS total_tokens,
  cc_attr_bigint(a, 'total_tool_uses')                           AS total_tool_uses,
  cc_attr(a, 'final_model')                                      AS final_model,
  cc_attr_bool(a, 'model_swapped')                               AS model_swapped,
  cc_attr(a, 'event_type')                                       AS event_type,
  cc_attr(a, 'appearance_id')                                    AS appearance_id,
  cc_attr(a, 'survey_type')                                      AS survey_type,
  cc_attr_bool(a, 'enabled_via_override')                        AS enabled_via_override,
  cc_attr(a, 'result')                                           AS result,
  cc_attr_bigint(a, 'period_days')                               AS period_days,
  cc_attr_bool(a, 'used_default')                                AS used_default,
  cc_attr(a, 'skip_reason')                                      AS skip_reason,
  cc_attr_bigint(a, 'transcripts_deleted')                       AS transcripts_deleted,
  cc_attr_bigint(a, 'transcripts_exempted_desktop')              AS transcripts_exempted_desktop,
  cc_attr_bigint(a, 'session_files_deleted')                     AS session_files_deleted,
  cc_attr_bigint(a, 'artifacts_deleted')                         AS artifacts_deleted,
  cc_attr_bigint(a, 'files_retained_fresh')                      AS files_retained_fresh,
  cc_attr_bigint(a, 'files_past_cutoff')                         AS files_past_cutoff,
  cc_attr_bigint(a, 'error_count')                               AS error_count,
  cc_attr(a, 'managed_settings.trigger')                         AS managed_settings_trigger,
  cc_attr_list(a, 'managed_settings.sources')                    AS managed_settings_sources,
  cc_attr(a, 'managed_settings.source_behavior')                 AS managed_settings_source_behavior,
  cc_attr(a, 'managed_settings.helper.state')                    AS managed_settings_helper_state,
  cc_attr(a, 'managed_settings.helper.applied')                  AS managed_settings_helper_applied,
  cc_attr(a, 'managed_settings.helper.entry')                    AS managed_settings_helper_entry,
  cc_attr(a, 'managed_settings.helper.path')                     AS managed_settings_helper_path,
  cc_attr(a, 'managed_settings.resolved_sha256')                 AS managed_settings_resolved_sha256,
  cc_attr(a, 'managed_settings.settings')                        AS managed_settings_settings,
  cc_attr_bool(a, 'managed_settings.settings_truncated')         AS managed_settings_settings_truncated,
  r.attributes                                                   AS attributes_list
FROM attrs;

-- Hot logs view: serialize attributes_list to JSON as the last column so any unpromoted key
-- stays reachable.
-- NULLIF wraps getenv() because DuckDB getenv() returns '' (empty string), NOT NULL, for an
-- unset var — so COALESCE alone would never fall back. NULLIF('','') → NULL → COALESCE picks
-- the repo-root-relative default. When CC_OTEL_STORE is set (absolute), it wins.
CREATE OR REPLACE VIEW cc_logs AS
SELECT * EXCLUDE (attributes_list), to_json(attributes_list) AS log_attributes_raw
FROM cc_logs_from(
  COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cc-logs.json');

-- Metrics projection (SSOT): Claude Code emits OTLP sums (token.usage, cost.usage,
-- active_time.total, lines_of_code.count, code_edit_tool.decision, session.count, ...).
-- Unnesting sum.dataPoints naturally restricts to Sum-type metrics — gauge/histogram
-- metrics (whose .sum is NULL) contribute no rows.
CREATE OR REPLACE MACRO cc_metrics_from(src) AS TABLE
WITH resource_metrics AS (
  SELECT unnest(resourceMetrics) AS rm
  FROM read_json_auto(src, format = 'newline_delimited', maximum_object_size = 33554432, sample_size = -1)
),
scope_metrics AS (
  SELECT unnest(rm.scopeMetrics) AS sm FROM resource_metrics
),
metric_rows AS (
  SELECT unnest(sm.metrics) AS m FROM scope_metrics
),
data_points AS (
  SELECT m.name AS metric_name, m.unit AS metric_unit, unnest(m.sum.dataPoints) AS dp
  FROM metric_rows
),
attrs AS (
  SELECT *, cc_attr_map(cc_attr_entries(dp.attributes)) AS a FROM data_points
)
SELECT
  make_timestamp(TRY_CAST(dp.timeUnixNano AS BIGINT) // 1000)   AS event_time,
  metric_name,
  metric_unit,
  -- value: asInt (quoted int64 → VARCHAR) on integer counters, asDouble on floating-point
  -- sums. Extracted via JSON, NOT native dp.asInt / dp.asDouble struct access: read_json_auto
  -- infers only the sub-keys present in the source, and a schema-thin slice (e.g. a prune's
  -- dropped temp on an all-asDouble day — observed live) binder-errors on a native reference
  -- to the absent key. json_extract_string returns NULL for a missing key instead.
  COALESCE(
    TRY_CAST(json_extract_string(to_json(dp), 'asDouble') AS DOUBLE),
    TRY_CAST(json_extract_string(to_json(dp), 'asInt') AS DOUBLE)
  )                                                              AS value,
  cc_attr(a, 'session.id')                                       AS session_id,
  cc_attr(a, 'model')                                            AS model,
  -- `type` distinguishes token sub-kinds on claude_code.token.usage
  -- (input / output / cacheRead / cacheCreation).
  cc_attr(a, 'type')                                             AS attr_type,
  cc_attr(a, 'terminal.type')                                    AS terminal_type,
  cc_attr(a, 'ccr.session.id')                                   AS ccr_session_id,
  cc_attr(a, 'app.version')                                      AS app_version,
  cc_attr(a, 'app.entrypoint')                                   AS app_entrypoint,
  cc_attr(a, 'organization.id')                                  AS organization_id,
  cc_attr(a, 'user.account_uuid')                                AS user_account_uuid,
  cc_attr(a, 'user.account_id')                                  AS user_account_id,
  cc_attr(a, 'user.id')                                          AS user_id,
  cc_attr(a, 'user.email')                                       AS user_email,
  cc_attr(a, 'user.groups')                                      AS user_groups,
  cc_attr(a, 'identity.source')                                  AS identity_source,
  cc_attr(a, 'vcs.repository.url.full')                          AS vcs_repository_url_full,
  cc_attr(a, 'vcs.owner.name')                                   AS vcs_owner_name,
  cc_attr(a, 'vcs.repository.name')                              AS vcs_repository_name,
  cc_attr(a, 'vcs.provider.name')                                AS vcs_provider_name,
  cc_attr(a, 'start_type')                                       AS start_type,
  cc_attr(a, 'query_source')                                     AS query_source,
  cc_attr(a, 'speed')                                            AS speed,
  cc_attr(a, 'effort')                                           AS effort,
  cc_attr(a, 'agent.name')                                       AS agent_name,
  cc_attr(a, 'skill.name')                                       AS skill_name,
  cc_attr(a, 'plugin.name')                                      AS plugin_name,
  cc_attr(a, 'marketplace.name')                                 AS marketplace_name,
  cc_attr(a, 'mcp_server.name')                                  AS mcp_server_name,
  cc_attr(a, 'mcp_tool.name')                                    AS mcp_tool_name,
  cc_attr(a, 'tool_name')                                        AS tool_name,
  cc_attr(a, 'decision')                                         AS decision,
  cc_attr(a, 'source')                                           AS source,
  cc_attr(a, 'language')                                         AS language,
  dp.attributes                                                  AS attributes_list
FROM attrs;

-- Hot metrics view: same CC_OTEL_STORE resolution as cc_logs (see the NULLIF note there).
CREATE OR REPLACE VIEW cc_metrics AS
SELECT * EXCLUDE (attributes_list), to_json(attributes_list) AS metric_attributes_raw
FROM cc_metrics_from(
  COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cc-metrics.json');

-- Spans projection (SSOT): one typed row per trace span (interaction, llm_request, tool,
-- tool.execution, tool.blocked_on_user, hook). The attribute map also takes the attributes of
-- the span's tool.output event; a key on both keeps the span's own value. The events are read
-- through JSON so a store that never recorded one still binds. attributes_list stays the
-- span's own attribute array.
CREATE OR REPLACE MACRO cc_spans_from(src) AS TABLE
WITH resource_spans AS (
  SELECT unnest(resourceSpans) AS rs
  FROM read_json_auto(src, format = 'newline_delimited', maximum_object_size = 33554432, sample_size = -1)
),
scope_spans AS (
  SELECT unnest(rs.scopeSpans) AS ss FROM resource_spans
),
span_rows AS (
  SELECT unnest(ss.spans) AS s FROM scope_spans
),
attrs AS (
  SELECT s, cc_attr_map(list_concat(
    cc_attr_entries(s.attributes),
    flatten(list_transform(
      list_filter(
        from_json(json_extract(to_json(s), '$.events'), '[{"name":"VARCHAR","attributes":[{"key":"VARCHAR","value":"JSON"}]}]'),
        lambda e: e.name = 'tool.output'),
      lambda e: e.attributes)))) AS a
  FROM span_rows
)
SELECT
  make_timestamp(TRY_CAST(s.startTimeUnixNano AS BIGINT) // 1000) AS span_time,
  make_timestamp(TRY_CAST(s.endTimeUnixNano AS BIGINT) // 1000)   AS end_time,
  s.traceId                                                      AS trace_id,
  s.spanId                                                       AS span_id,
  json_extract_string(to_json(s), '$.parentSpanId')              AS parent_span_id,
  s.name                                                         AS span_name,
  cc_attr(a, 'session.id')                                       AS session_id,
  cc_attr(a, 'span.type')                                        AS span_type,
  cc_attr(a, 'tool_name')                                        AS tool_name,
  cc_attr(a, 'tool_use_id')                                      AS tool_use_id,
  cc_attr(a, 'prompt.id')                                        AS prompt_id,
  cc_attr(a, 'model')                                            AS model,
  -- Interaction spans carry the prompt only when content capture is on; cold compaction
  -- scrubs it unless CC_OTEL_COLD_KEEP_USER_PROMPTS=1 (same knob as logs).
  cc_attr(a, 'user_prompt')                                      AS user_prompt,
  cc_attr(a, 'success')                                          AS success,
  cc_attr_double(a, 'duration_ms')                               AS duration_ms,
  cc_attr(a, 'ccr.session.id')                                   AS ccr_session_id,
  cc_attr(a, 'app.version')                                      AS app_version,
  cc_attr(a, 'app.entrypoint')                                   AS app_entrypoint,
  cc_attr(a, 'organization.id')                                  AS organization_id,
  cc_attr(a, 'user.account_uuid')                                AS user_account_uuid,
  cc_attr(a, 'user.account_id')                                  AS user_account_id,
  cc_attr(a, 'user.id')                                          AS user_id,
  cc_attr(a, 'user.email')                                       AS user_email,
  cc_attr(a, 'user.groups')                                      AS user_groups,
  cc_attr(a, 'identity.source')                                  AS identity_source,
  cc_attr(a, 'vcs.repository.url.full')                          AS vcs_repository_url_full,
  cc_attr(a, 'vcs.owner.name')                                   AS vcs_owner_name,
  cc_attr(a, 'vcs.repository.name')                              AS vcs_repository_name,
  cc_attr(a, 'vcs.provider.name')                                AS vcs_provider_name,
  cc_attr(a, 'terminal.type')                                    AS terminal_type,
  cc_attr(a, 'workflow.run_id')                                  AS workflow_run_id,
  cc_attr(a, 'workflow.name')                                    AS workflow_name,
  cc_attr_bigint(a, 'user_prompt_length')                        AS user_prompt_length,
  cc_attr_bigint(a, 'interaction.sequence')                      AS interaction_sequence,
  cc_attr_double(a, 'interaction.duration_ms')                   AS interaction_duration_ms,
  cc_attr(a, 'parent.source')                                    AS parent_source,
  cc_attr(a, 'gen_ai.system')                                    AS gen_ai_system,
  cc_attr(a, 'gen_ai.request.model')                             AS gen_ai_request_model,
  cc_attr(a, 'query_source')                                     AS query_source,
  cc_attr(a, 'query_source_safe')                                AS query_source_safe,
  cc_attr(a, 'agent_id')                                         AS agent_id,
  cc_attr(a, 'parent_agent_id')                                  AS parent_agent_id,
  cc_attr(a, 'speed')                                            AS speed,
  cc_attr(a, 'effort')                                           AS effort,
  cc_attr(a, 'llm_request.context')                              AS llm_request_context,
  cc_attr_double(a, 'ttft_ms')                                   AS ttft_ms,
  cc_attr_double(a, 'first_content_ms')                          AS first_content_ms,
  cc_attr_bigint(a, 'input_tokens')                              AS input_tokens,
  cc_attr_bigint(a, 'output_tokens')                             AS output_tokens,
  cc_attr_bigint(a, 'cache_read_tokens')                         AS cache_read_tokens,
  cc_attr_bigint(a, 'cache_creation_tokens')                     AS cache_creation_tokens,
  cc_attr(a, 'request_id')                                       AS request_id,
  cc_attr(a, 'gen_ai.response.id')                               AS gen_ai_response_id,
  cc_attr(a, 'client_request_id')                                AS client_request_id,
  cc_attr_bigint(a, 'attempt')                                   AS attempt,
  cc_attr_bigint(a, 'status_code')                               AS status_code,
  cc_attr(a, 'error')                                            AS error,
  cc_attr(a, 'error_class')                                      AS error_class,
  cc_attr_bool(a, 'response.has_tool_call')                      AS response_has_tool_call,
  cc_attr(a, 'stop_reason')                                      AS stop_reason,
  cc_attr_list(a, 'gen_ai.response.finish_reasons')              AS gen_ai_response_finish_reasons,
  cc_attr(a, 'tool_name_safe')                                   AS tool_name_safe,
  cc_attr(a, 'bash_command_class')                               AS bash_command_class,
  cc_attr(a, 'bash_argv0')                                       AS bash_argv0,
  cc_attr_bigint(a, 'result_tokens')                             AS result_tokens,
  cc_attr(a, 'gen_ai.tool.call.id')                              AS gen_ai_tool_call_id,
  cc_attr(a, 'file_path')                                        AS file_path,
  cc_attr(a, 'full_command')                                     AS full_command,
  cc_attr(a, 'skill_name')                                       AS skill_name,
  cc_attr(a, 'subagent_type')                                    AS subagent_type,
  cc_attr(a, 'content')                                          AS content,
  cc_attr(a, 'output')                                           AS output,
  cc_attr(a, 'diff')                                             AS diff,
  cc_attr(a, 'bash_command')                                     AS bash_command,
  cc_attr(a, 'decision')                                         AS decision,
  cc_attr(a, 'source')                                           AS source,
  cc_attr(a, 'hook_event')                                       AS hook_event,
  cc_attr(a, 'hook_name')                                        AS hook_name,
  cc_attr_bigint(a, 'num_hooks')                                 AS num_hooks,
  cc_attr_bigint(a, 'num_success')                               AS num_success,
  cc_attr_bigint(a, 'num_blocking')                              AS num_blocking,
  cc_attr_bigint(a, 'num_non_blocking_error')                    AS num_non_blocking_error,
  cc_attr_bigint(a, 'num_cancelled')                             AS num_cancelled,
  cc_attr(a, 'hook_definitions')                                 AS hook_definitions,
  cc_attr(a, 'new_context')                                      AS new_context,
  cc_attr(a, 'system_prompt_preview')                            AS system_prompt_preview,
  cc_attr(a, 'user_system_prompt')                               AS user_system_prompt,
  cc_attr(a, 'tool_input')                                       AS tool_input,
  cc_attr(a, 'response.model_output')                            AS response_model_output,
  s.attributes                                                   AS attributes_list
FROM attrs;

CREATE OR REPLACE VIEW cc_spans AS
SELECT * EXCLUDE (attributes_list), to_json(attributes_list) AS span_attributes_raw
FROM cc_spans_from(
  COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cc-traces.json');

-- One row per trace_id — root interaction metadata + span counts for quick scans.
CREATE OR REPLACE VIEW cc_traces AS
SELECT
  trace_id,
  min(session_id)                                                                             AS session_id,
  min(span_time)                                                                              AS start_time,
  max(end_time)                                                                               AS end_time,
  count(*)::BIGINT                                                                            AS span_count,
  max(CASE WHEN span_name = 'claude_code.interaction' THEN duration_ms END)                   AS interaction_duration_ms,
  max(CASE WHEN span_name = 'claude_code.interaction' THEN user_prompt END)                   AS user_prompt
FROM cc_spans
GROUP BY trace_id;

-- Cold tier: structure history compacted by prune-otel-store.sh to ZSTD Parquet under
-- <store>/cold/, one file per prune run (append-only — a failed compaction never corrupts
-- prior cold history). The Parquet was written FROM the macros above (the compaction step
-- serializes/scrubs attributes_list into *_attributes_raw), but a file compacted before a
-- column was promoted lacks that column. Each cold macro therefore unions BY NAME a typed
-- zero-row stub of the hot column contract with the files read union_by_name: cold always
-- exposes hot's names, order and types, a column a file lacks reads NULL, and
-- `SELECT ... FROM cc_logs UNION ALL SELECT ... FROM cc_logs_cold()` binds positionally. The
-- stubs below must list the hot views' columns in order (cc-otel.test.sh compares DESCRIBE).
-- Query with parentheses — these are zero-arg-callable table macros, NOT views,
-- so that an empty cold/ glob errors lazily at query time instead of killing this init file
-- (see the header note on error posture).
-- Content boundary (enforced at compaction, documented here for queriers): no
-- api_request_body/api_response_body rows. Unless CC_OTEL_COLD_KEEP_USER_PROMPTS=1 was set at
-- prune time, user_prompt rows have body NULL, the logs `prompt` and spans `user_prompt`
-- columns are NULL, and the `prompt`, `prompt_text` and `user_prompt` attributes are scrubbed
-- from the raw JSON. With CC_OTEL_COLD_KEEP_CONTENT=0 at prune time, the rest of the content
-- class is NULLed and scrubbed the same way: response and model-output text, tool payloads
-- (content, output, diff, new_context, tool_input, tool_parameters), command strings
-- (full_command, bash_command), error text (error), configuration text (hook_definitions,
-- hook_matcher, system_prompt_preview, user_system_prompt, managed_settings_settings), identity
-- (user_email) and absolute paths (file_path, body_ref, workspace_host_paths,
-- managed_settings_helper_path). By default (unset or 1) that class is kept.
CREATE OR REPLACE MACRO cc_logs_cold_stub() AS TABLE
SELECT
  NULL::TIMESTAMP AS event_time, NULL::VARCHAR AS session_id, NULL::VARCHAR AS event_name,
  NULL::VARCHAR AS tool_name, NULL::VARCHAR AS hook_name, NULL::VARCHAR AS decision,
  NULL::DOUBLE AS duration_ms, NULL::VARCHAR AS success, NULL::VARCHAR AS source,
  NULL::VARCHAR AS prompt_id, NULL::VARCHAR AS tool_use_id, NULL::VARCHAR AS terminal_type,
  NULL::BIGINT AS event_sequence, NULL::VARCHAR AS trace_id, NULL::VARCHAR AS span_id,
  NULL::VARCHAR AS body, NULL::VARCHAR AS ccr_session_id, NULL::VARCHAR AS app_version,
  NULL::VARCHAR AS app_entrypoint, NULL::VARCHAR AS organization_id,
  NULL::VARCHAR AS user_account_uuid, NULL::VARCHAR AS user_account_id, NULL::VARCHAR AS user_id,
  NULL::VARCHAR AS user_email, NULL::VARCHAR AS user_groups, NULL::VARCHAR AS identity_source,
  NULL::VARCHAR AS vcs_repository_url_full, NULL::VARCHAR AS vcs_owner_name,
  NULL::VARCHAR AS vcs_repository_name, NULL::VARCHAR AS vcs_provider_name,
  NULL::VARCHAR[] AS workspace_host_paths, NULL::VARCHAR AS workflow_run_id,
  NULL::VARCHAR AS workflow_name, NULL::VARCHAR AS event_timestamp, NULL::VARCHAR AS message_uuid,
  NULL::VARCHAR AS message_id, NULL::VARCHAR AS request_id, NULL::VARCHAR AS client_request_id,
  NULL::VARCHAR AS model, NULL::VARCHAR AS query_source, NULL::VARCHAR AS speed,
  NULL::VARCHAR AS effort, NULL::VARCHAR AS agent_name, NULL::VARCHAR AS skill_name,
  NULL::VARCHAR AS plugin_name, NULL::VARCHAR AS marketplace_name,
  NULL::VARCHAR AS mcp_server_name, NULL::VARCHAR AS mcp_tool_name, NULL::BIGINT AS prompt_length,
  NULL::VARCHAR AS prompt, NULL::VARCHAR AS command_name, NULL::VARCHAR AS command_source,
  NULL::BIGINT AS response_length, NULL::VARCHAR AS response, NULL::VARCHAR AS error_type,
  NULL::VARCHAR AS error, NULL::VARCHAR AS decision_type, NULL::BIGINT AS tool_input_size_bytes,
  NULL::BIGINT AS tool_result_size_bytes, NULL::VARCHAR AS mcp_server_scope,
  NULL::VARCHAR AS vcs_ref_head_revision, NULL::VARCHAR AS vcs_ref_head_name,
  NULL::VARCHAR AS vcs_ref_head_type, NULL::VARCHAR AS tool_parameters,
  NULL::VARCHAR AS tool_input, NULL::VARCHAR AS tool_source, NULL::DOUBLE AS cost_usd,
  NULL::BIGINT AS cost_usd_micros, NULL::BIGINT AS input_tokens, NULL::BIGINT AS output_tokens,
  NULL::BIGINT AS cache_read_tokens, NULL::BIGINT AS cache_creation_tokens,
  NULL::BIGINT AS status_code, NULL::BIGINT AS attempt, NULL::BOOLEAN AS server_fallback_hop,
  NULL::BOOLEAN AS has_category, NULL::BOOLEAN AS has_explanation, NULL::VARCHAR AS category,
  NULL::VARCHAR AS body_ref, NULL::BIGINT AS body_length, NULL::BOOLEAN AS body_truncated,
  NULL::VARCHAR AS request_body_id, NULL::VARCHAR AS from_mode, NULL::VARCHAR AS to_mode,
  NULL::VARCHAR AS trigger, NULL::VARCHAR AS action, NULL::VARCHAR AS auth_method,
  NULL::VARCHAR AS error_category, NULL::VARCHAR AS status, NULL::VARCHAR AS transport_type,
  NULL::VARCHAR AS server_scope, NULL::VARCHAR AS server_name, NULL::VARCHAR AS error_code,
  NULL::VARCHAR AS error_name, NULL::BOOLEAN AS is_plugin, NULL::VARCHAR AS plugin_id,
  NULL::VARCHAR AS plugin_id_hash, NULL::VARCHAR AS plugin_version, NULL::VARCHAR AS plugin_scope,
  NULL::BOOLEAN AS marketplace_is_official, NULL::VARCHAR AS install_trigger,
  NULL::VARCHAR AS enabled_via, NULL::BOOLEAN AS has_hooks, NULL::BOOLEAN AS has_mcp,
  NULL::BOOLEAN AS host_owned_mcp, NULL::BIGINT AS skill_path_count,
  NULL::BIGINT AS command_path_count, NULL::BIGINT AS agent_path_count, NULL::BOOLEAN AS safe_mode,
  NULL::VARCHAR AS invocation_trigger, NULL::VARCHAR AS skill_source, NULL::VARCHAR AS skill_kind,
  NULL::VARCHAR AS mention_type, NULL::BIGINT AS total_attempts,
  NULL::DOUBLE AS total_retry_duration_ms, NULL::VARCHAR AS hook_event, NULL::VARCHAR AS hook_type,
  NULL::VARCHAR AS hook_source, NULL::VARCHAR AS hook_matcher, NULL::VARCHAR AS hook_definitions,
  NULL::BOOLEAN AS managed_only, NULL::BIGINT AS num_hooks, NULL::BIGINT AS num_success,
  NULL::BIGINT AS num_blocking, NULL::BIGINT AS num_non_blocking_error,
  NULL::BIGINT AS num_cancelled, NULL::DOUBLE AS total_duration_ms, NULL::BIGINT AS stdout_chars,
  NULL::BIGINT AS additional_context_chars, NULL::BIGINT AS system_message_chars,
  NULL::BIGINT AS initial_user_message_chars, NULL::BIGINT AS num_outputs_persisted,
  NULL::BIGINT AS pre_tokens, NULL::BIGINT AS post_tokens, NULL::VARCHAR AS precompute_reuse,
  NULL::VARCHAR AS agent_type, NULL::VARCHAR AS agent_source, NULL::BOOLEAN AS is_built_in,
  NULL::BOOLEAN AS is_async, NULL::BIGINT AS total_tokens, NULL::BIGINT AS total_tool_uses,
  NULL::VARCHAR AS final_model, NULL::BOOLEAN AS model_swapped, NULL::VARCHAR AS event_type,
  NULL::VARCHAR AS appearance_id, NULL::VARCHAR AS survey_type,
  NULL::BOOLEAN AS enabled_via_override, NULL::VARCHAR AS result, NULL::BIGINT AS period_days,
  NULL::BOOLEAN AS used_default, NULL::VARCHAR AS skip_reason, NULL::BIGINT AS transcripts_deleted,
  NULL::BIGINT AS transcripts_exempted_desktop, NULL::BIGINT AS session_files_deleted,
  NULL::BIGINT AS artifacts_deleted, NULL::BIGINT AS files_retained_fresh,
  NULL::BIGINT AS files_past_cutoff, NULL::BIGINT AS error_count,
  NULL::VARCHAR AS managed_settings_trigger, NULL::VARCHAR[] AS managed_settings_sources,
  NULL::VARCHAR AS managed_settings_source_behavior,
  NULL::VARCHAR AS managed_settings_helper_state, NULL::VARCHAR AS managed_settings_helper_applied,
  NULL::VARCHAR AS managed_settings_helper_entry, NULL::VARCHAR AS managed_settings_helper_path,
  NULL::VARCHAR AS managed_settings_resolved_sha256, NULL::VARCHAR AS managed_settings_settings,
  NULL::BOOLEAN AS managed_settings_settings_truncated, NULL::JSON AS log_attributes_raw
LIMIT 0;

CREATE OR REPLACE MACRO cc_metrics_cold_stub() AS TABLE
SELECT
  NULL::TIMESTAMP AS event_time, NULL::VARCHAR AS metric_name, NULL::VARCHAR AS metric_unit,
  NULL::DOUBLE AS value, NULL::VARCHAR AS session_id, NULL::VARCHAR AS model,
  NULL::VARCHAR AS attr_type, NULL::VARCHAR AS terminal_type, NULL::VARCHAR AS ccr_session_id,
  NULL::VARCHAR AS app_version, NULL::VARCHAR AS app_entrypoint, NULL::VARCHAR AS organization_id,
  NULL::VARCHAR AS user_account_uuid, NULL::VARCHAR AS user_account_id, NULL::VARCHAR AS user_id,
  NULL::VARCHAR AS user_email, NULL::VARCHAR AS user_groups, NULL::VARCHAR AS identity_source,
  NULL::VARCHAR AS vcs_repository_url_full, NULL::VARCHAR AS vcs_owner_name,
  NULL::VARCHAR AS vcs_repository_name, NULL::VARCHAR AS vcs_provider_name,
  NULL::VARCHAR AS start_type, NULL::VARCHAR AS query_source, NULL::VARCHAR AS speed,
  NULL::VARCHAR AS effort, NULL::VARCHAR AS agent_name, NULL::VARCHAR AS skill_name,
  NULL::VARCHAR AS plugin_name, NULL::VARCHAR AS marketplace_name,
  NULL::VARCHAR AS mcp_server_name, NULL::VARCHAR AS mcp_tool_name, NULL::VARCHAR AS tool_name,
  NULL::VARCHAR AS decision, NULL::VARCHAR AS source, NULL::VARCHAR AS language,
  NULL::JSON AS metric_attributes_raw
LIMIT 0;

CREATE OR REPLACE MACRO cc_spans_cold_stub() AS TABLE
SELECT
  NULL::TIMESTAMP AS span_time, NULL::TIMESTAMP AS end_time, NULL::VARCHAR AS trace_id,
  NULL::VARCHAR AS span_id, NULL::VARCHAR AS parent_span_id, NULL::VARCHAR AS span_name,
  NULL::VARCHAR AS session_id, NULL::VARCHAR AS span_type, NULL::VARCHAR AS tool_name,
  NULL::VARCHAR AS tool_use_id, NULL::VARCHAR AS prompt_id, NULL::VARCHAR AS model,
  NULL::VARCHAR AS user_prompt, NULL::VARCHAR AS success, NULL::DOUBLE AS duration_ms,
  NULL::VARCHAR AS ccr_session_id, NULL::VARCHAR AS app_version, NULL::VARCHAR AS app_entrypoint,
  NULL::VARCHAR AS organization_id, NULL::VARCHAR AS user_account_uuid,
  NULL::VARCHAR AS user_account_id, NULL::VARCHAR AS user_id, NULL::VARCHAR AS user_email,
  NULL::VARCHAR AS user_groups, NULL::VARCHAR AS identity_source,
  NULL::VARCHAR AS vcs_repository_url_full, NULL::VARCHAR AS vcs_owner_name,
  NULL::VARCHAR AS vcs_repository_name, NULL::VARCHAR AS vcs_provider_name,
  NULL::VARCHAR AS terminal_type, NULL::VARCHAR AS workflow_run_id, NULL::VARCHAR AS workflow_name,
  NULL::BIGINT AS user_prompt_length, NULL::BIGINT AS interaction_sequence,
  NULL::DOUBLE AS interaction_duration_ms, NULL::VARCHAR AS parent_source,
  NULL::VARCHAR AS gen_ai_system, NULL::VARCHAR AS gen_ai_request_model,
  NULL::VARCHAR AS query_source, NULL::VARCHAR AS query_source_safe, NULL::VARCHAR AS agent_id,
  NULL::VARCHAR AS parent_agent_id, NULL::VARCHAR AS speed, NULL::VARCHAR AS effort,
  NULL::VARCHAR AS llm_request_context, NULL::DOUBLE AS ttft_ms, NULL::DOUBLE AS first_content_ms,
  NULL::BIGINT AS input_tokens, NULL::BIGINT AS output_tokens, NULL::BIGINT AS cache_read_tokens,
  NULL::BIGINT AS cache_creation_tokens, NULL::VARCHAR AS request_id,
  NULL::VARCHAR AS gen_ai_response_id, NULL::VARCHAR AS client_request_id, NULL::BIGINT AS attempt,
  NULL::BIGINT AS status_code, NULL::VARCHAR AS error, NULL::VARCHAR AS error_class,
  NULL::BOOLEAN AS response_has_tool_call, NULL::VARCHAR AS stop_reason,
  NULL::VARCHAR[] AS gen_ai_response_finish_reasons, NULL::VARCHAR AS tool_name_safe,
  NULL::VARCHAR AS bash_command_class, NULL::VARCHAR AS bash_argv0, NULL::BIGINT AS result_tokens,
  NULL::VARCHAR AS gen_ai_tool_call_id, NULL::VARCHAR AS file_path, NULL::VARCHAR AS full_command,
  NULL::VARCHAR AS skill_name, NULL::VARCHAR AS subagent_type, NULL::VARCHAR AS content,
  NULL::VARCHAR AS output, NULL::VARCHAR AS diff, NULL::VARCHAR AS bash_command,
  NULL::VARCHAR AS decision, NULL::VARCHAR AS source, NULL::VARCHAR AS hook_event,
  NULL::VARCHAR AS hook_name, NULL::BIGINT AS num_hooks, NULL::BIGINT AS num_success,
  NULL::BIGINT AS num_blocking, NULL::BIGINT AS num_non_blocking_error,
  NULL::BIGINT AS num_cancelled, NULL::VARCHAR AS hook_definitions, NULL::VARCHAR AS new_context,
  NULL::VARCHAR AS system_prompt_preview, NULL::VARCHAR AS user_system_prompt,
  NULL::VARCHAR AS tool_input, NULL::VARCHAR AS response_model_output,
  NULL::JSON AS span_attributes_raw
LIMIT 0;

CREATE OR REPLACE MACRO cc_logs_cold(src := COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cold/cc-logs-*.parquet') AS TABLE
SELECT * FROM cc_logs_cold_stub() UNION ALL BY NAME SELECT * FROM read_parquet(src, union_by_name = true);

CREATE OR REPLACE MACRO cc_metrics_cold(src := COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cold/cc-metrics-*.parquet') AS TABLE
SELECT * FROM cc_metrics_cold_stub() UNION ALL BY NAME SELECT * FROM read_parquet(src, union_by_name = true);

CREATE OR REPLACE MACRO cc_spans_cold(src := COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cold/cc-traces-*.parquet') AS TABLE
SELECT * FROM cc_spans_cold_stub() UNION ALL BY NAME SELECT * FROM read_parquet(src, union_by_name = true);
