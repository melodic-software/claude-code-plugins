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
-- | {boolValue}); a single key is pulled with list_filter(attrs, lambda x: x.key='<k>')[1].
-- Native read_json unnests the attribute arrays and reads the full multi-MB store in a
-- single pass.
--
-- The macros surface the attribute array as an internal attributes_list column (typed LIST,
-- last position); each consumer serializes it (to_json -> *_attributes_raw) or scrubs it
-- (cold compaction's privacy boundary) as its final step. Column names/order/types of the
-- hot views are unchanged by this indirection.
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
-- only needs the macros below and deliberately points CC_OTEL_STORE at an empty dir so the
-- hot-view binds fail fast instead of re-inferring the full store schema per COPY.
.bail off

-- Logs projection (SSOT): one typed row per Claude Code event. The promoted columns are
-- pulled from each logRecord's attribute array; the full array rides along as
-- attributes_list (last column) for the consumer to serialize or scrub. Hook events carry
-- hook_name + decision; tool/api events carry tool_name + duration_ms — columns are NULL
-- where the event type does not emit that attribute.
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
)
SELECT
  make_timestamp(TRY_CAST(r.timeUnixNano AS BIGINT) // 1000)                               AS event_time,
  list_filter(r.attributes, lambda x: x.key = 'session.id')[1].value.stringValue           AS session_id,
  list_filter(r.attributes, lambda x: x.key = 'event.name')[1].value.stringValue           AS event_name,
  list_filter(r.attributes, lambda x: x.key = 'tool_name')[1].value.stringValue            AS tool_name,
  list_filter(r.attributes, lambda x: x.key = 'hook_name')[1].value.stringValue            AS hook_name,
  list_filter(r.attributes, lambda x: x.key = 'decision')[1].value.stringValue             AS decision,
  -- duration_ms is emitted as intValue on some events and stringValue on others, so COALESCE
  -- the two scalar sub-keys (both surface as VARCHAR) before casting.
  TRY_CAST(COALESCE(
    list_filter(r.attributes, lambda x: x.key = 'duration_ms')[1].value.stringValue,
    list_filter(r.attributes, lambda x: x.key = 'duration_ms')[1].value.intValue
  ) AS DOUBLE)                                                                             AS duration_ms,
  list_filter(r.attributes, lambda x: x.key = 'success')[1].value.stringValue              AS success,
  list_filter(r.attributes, lambda x: x.key = 'decision_source')[1].value.stringValue      AS decision_source,
  list_filter(r.attributes, lambda x: x.key = 'prompt.id')[1].value.stringValue            AS prompt_id,
  list_filter(r.attributes, lambda x: x.key = 'tool_use_id')[1].value.stringValue          AS tool_use_id,
  list_filter(r.attributes, lambda x: x.key = 'terminal.type')[1].value.stringValue        AS terminal_type,
  TRY_CAST(list_filter(r.attributes, lambda x: x.key = 'event.sequence')[1].value.intValue AS BIGINT) AS event_sequence,
  r.traceId                                                                                AS trace_id,
  r.spanId                                                                                 AS span_id,
  r.body.stringValue                                                                       AS body,
  r.attributes                                                                             AS attributes_list
FROM records;

-- Hot logs view: serialize attributes_list to JSON as the last column so any unpromoted key
-- stays reachable. Column contract is byte-identical to the pre-macro view.
-- NULLIF wraps getenv() because DuckDB getenv() returns '' (empty string), NOT NULL, for an
-- unset var — so COALESCE alone would never fall back. NULLIF('','') → NULL → COALESCE picks
-- the repo-root-relative default. When CC_OTEL_STORE is set (absolute), it wins.
CREATE OR REPLACE VIEW cc_logs AS
SELECT * EXCLUDE (attributes_list), to_json(attributes_list) AS log_attributes_raw
FROM cc_logs_from(
  COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cc-logs.json');

-- Metrics projection (SSOT): Claude Code emits OTLP sums (token.usage, cost.usage,
-- active_time.total, lines_of_code.count, code_edit_tool.decision, session.count).
-- Unnesting sum.dataPoints naturally restricts to Sum-type metrics — gauge/histogram
-- metrics (whose .sum is NULL) contribute no rows. Each data point's attribute array
-- carries session.id / model / token type / terminal.type, etc.
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
)
SELECT
  make_timestamp(TRY_CAST(dp.timeUnixNano AS BIGINT) // 1000)                              AS event_time,
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
  )                                                                                        AS value,
  list_filter(dp.attributes, lambda x: x.key = 'session.id')[1].value.stringValue          AS session_id,
  list_filter(dp.attributes, lambda x: x.key = 'model')[1].value.stringValue               AS model,
  -- `type` distinguishes token sub-kinds on claude_code.token.usage
  -- (input / output / cacheRead / cacheCreation).
  list_filter(dp.attributes, lambda x: x.key = 'type')[1].value.stringValue                AS attr_type,
  list_filter(dp.attributes, lambda x: x.key = 'terminal.type')[1].value.stringValue       AS terminal_type,
  dp.attributes                                                                            AS attributes_list
FROM data_points;

-- Hot metrics view: same CC_OTEL_STORE resolution as cc_logs (see the NULLIF note there).
CREATE OR REPLACE VIEW cc_metrics AS
SELECT * EXCLUDE (attributes_list), to_json(attributes_list) AS metric_attributes_raw
FROM cc_metrics_from(
  COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cc-metrics.json');

-- Spans projection (SSOT): one typed row per trace span. Promoted columns mirror the CC beta
-- span catalog (interaction, llm_request, tool, tool.execution, tool.blocked_on_user, hook).
-- user_prompt is promoted for interaction spans when content capture is on — cold compaction
-- scrubs it unless CC_OTEL_COLD_KEEP_USER_PROMPTS=1 (same knob as logs).
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
)
SELECT
  make_timestamp(TRY_CAST(s.startTimeUnixNano AS BIGINT) // 1000)                               AS span_time,
  make_timestamp(TRY_CAST(s.endTimeUnixNano AS BIGINT) // 1000)                                 AS end_time,
  s.traceId                                                                                     AS trace_id,
  s.spanId                                                                                      AS span_id,
  json_extract_string(to_json(s), '$.parentSpanId')                                             AS parent_span_id,
  s.name                                                                                        AS span_name,
  json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'session.id')[1]), '$.value.stringValue') AS session_id,
  json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'span.type')[1]), '$.value.stringValue') AS span_type,
  json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'tool_name')[1]), '$.value.stringValue') AS tool_name,
  json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'tool_use_id')[1]), '$.value.stringValue') AS tool_use_id,
  json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'prompt.id')[1]), '$.value.stringValue') AS prompt_id,
  json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'model')[1]), '$.value.stringValue') AS model,
  json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'user_prompt')[1]), '$.value.stringValue') AS user_prompt,
  json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'success')[1]), '$.value.stringValue') AS success,
  TRY_CAST(COALESCE(
    json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'duration_ms')[1]), '$.value.stringValue'),
    json_extract_string(to_json(list_filter(s.attributes, lambda x: x.key = 'duration_ms')[1]), '$.value.intValue')
  ) AS DOUBLE)                                                                                  AS duration_ms,
  s.attributes                                                                                  AS attributes_list
FROM span_rows;

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
-- prior cold history). The Parquet was written FROM the macros above with the same final
-- column contract as the hot views (the compaction step serializes/scrubs attributes_list
-- into *_attributes_raw), so SELECT * here exposes identical names/order and
-- `SELECT ... FROM cc_logs UNION ALL SELECT ... FROM cc_logs_cold()` works without column
-- gymnastics. Query with parentheses — these are zero-arg-callable table macros, NOT views,
-- so that an empty cold/ glob errors lazily at query time instead of killing this init file
-- (see the header note on error posture).
-- Content boundary (enforced at compaction, documented here for queriers): no
-- api_request_body/api_response_body rows; user_prompt rows have body NULL and the `prompt`
-- attribute scrubbed unless CC_OTEL_COLD_KEEP_USER_PROMPTS=1 was set at prune time.
CREATE OR REPLACE MACRO cc_logs_cold(src := COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cold/cc-logs-*.parquet') AS TABLE
SELECT * FROM read_parquet(src);

CREATE OR REPLACE MACRO cc_metrics_cold(src := COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cold/cc-metrics-*.parquet') AS TABLE
SELECT * FROM read_parquet(src);

CREATE OR REPLACE MACRO cc_spans_cold(src := COALESCE(NULLIF(getenv('CC_OTEL_STORE'), ''), '.claude/observability/otel') || '/cold/cc-traces-*.parquet') AS TABLE
SELECT * FROM read_parquet(src);
