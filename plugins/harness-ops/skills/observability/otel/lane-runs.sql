-- lane-runs.sql: DuckDB views over the lane transcript sink that scripts/lane-transcripts/pull.mjs
-- writes in claude-code-plugins: lane_runs (metrics.jsonl, one row per CI lane leg) and
-- lane_outcomes (outcomes.jsonl, one row per lane-outcome record). Both carry trace_id, the
-- run attempt's trace id, so they join on it, and a span Claude Code exported under that trace
-- joins cc_spans the same way.
--
-- The sink resolves as the puller resolves it: LANE_TRANSCRIPT_SINK, else
-- $XDG_DATA_HOME/lane-transcripts, else ~/.local/share/lane-transcripts.
--   duckdb -init ${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/lane-runs.sql -c "SELECT count(*) FROM lane_runs;"
-- With the OTEL views as well, load cc-otel.sql first and read this file after it:
--   duckdb -init .../otel/cc-otel.sql -cmd ".read .../otel/lane-runs.sql"
--
-- The columns are named, so a row written before a field existed reads NULL there, and a field
-- added later is ignored until it is named here. total_cost_usd and model_usage cost_usd are the
-- CLI's own estimate, not a bill: https://code.claude.com/docs/en/costs#track-your-costs
--
-- Kept out of cc-otel.sql: prune-otel-store.sh loads that file for every compaction, and these
-- views bind the sink's files. A view whose file does not exist yet fails to bind; `.bail off`
-- keeps the other one loading.
.bail off

CREATE OR REPLACE MACRO lane_sink() AS COALESCE(
  NULLIF(getenv('LANE_TRANSCRIPT_SINK'), ''),
  NULLIF(getenv('XDG_DATA_HOME'), '') || '/lane-transcripts',
  getenv('HOME') || '/.local/share/lane-transcripts');

CREATE OR REPLACE VIEW lane_runs AS
SELECT *
FROM read_json(lane_sink() || '/metrics.jsonl', format = 'newline_delimited', columns = {
  provider: 'VARCHAR', run_ref: 'VARCHAR', run_url: 'VARCHAR', leg_key: 'VARCHAR',
  artifact_id: 'BIGINT', run_id: 'BIGINT', run_attempt: 'INTEGER', job_id: 'VARCHAR',
  lane: 'VARCHAR', workflow: 'VARCHAR', event: 'VARCHAR', head_branch: 'VARCHAR',
  run_conclusion: 'VARCHAR', created_at: 'TIMESTAMP', date: 'DATE',
  model: 'VARCHAR', models: 'VARCHAR[]', outcome: 'VARCHAR', subtype: 'VARCHAR',
  is_error: 'BOOLEAN', api_error_status: 'INTEGER', num_turns: 'INTEGER', duration_ms: 'BIGINT',
  input_tokens: 'BIGINT', output_tokens: 'BIGINT',
  cache_read_input_tokens: 'BIGINT', cache_creation_input_tokens: 'BIGINT',
  total_cost_usd: 'DOUBLE', model_usage: 'JSON',
  trace_id: 'VARCHAR', failure_class: 'VARCHAR', failure_class_source: 'VARCHAR',
  transcript_bytes: 'BIGINT', transcript: 'VARCHAR', pruned: 'VARCHAR', pulled_at: 'TIMESTAMP'
});

CREATE OR REPLACE VIEW lane_outcomes AS
SELECT run_id, run_attempt, trace_id, check_run_id, job_name, lane, workflow, created_at, date,
  record ->> 'outcome' AS outcome,
  record ->> 'class' AS failure_class,
  TRY_CAST(record ->> 'handoff' AS BOOLEAN) AS handoff,
  record -> 'credential' ->> 'kind' AS credential_kind,
  record,
FROM read_json(lane_sink() || '/outcomes.jsonl', format = 'newline_delimited', columns = {
  run_id: 'BIGINT', run_attempt: 'INTEGER', trace_id: 'VARCHAR', check_run_id: 'BIGINT',
  job_name: 'VARCHAR', lane: 'VARCHAR', workflow: 'VARCHAR', created_at: 'TIMESTAMP',
  date: 'DATE', record: 'JSON'
});
