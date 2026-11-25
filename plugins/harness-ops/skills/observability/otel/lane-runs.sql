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
