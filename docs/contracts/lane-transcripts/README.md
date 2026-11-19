# Lane transcripts: the sink layout readers rely on

A lane transcript sink holds the transcripts of CI lane legs, opened outside CI, with one metrics
row per leg. A *lane* is one CI workflow that runs Claude; a *run* is one execution of it; a *leg* is
one Claude CLI invocation inside a run (a credential leg, a fallback leg, a review chunk). A writer
fills the sink; a reader such as `/session-flow:retro ci-runs` reads it and nothing else. This file
is the contract between them: a writer may add fields, and a reader treats a field it does not know
as absent and a missing field as null.

The current writer is the GitHub puller, [`scripts/lane-transcripts/`](../../../scripts/lane-transcripts/README.md).
The current reader is the session-flow plugin's `scripts/lane_legs.py`.

## Layout

```text
<sink>/metrics.jsonl                                  one JSON row per leg, no transcript text
<sink>/outcomes.jsonl                                 one JSON row per lane-outcome record
<sink>/transcripts/<YYYY-MM-DD>/<lane>/<file>.json.gz  one leg's transcript
<sink>/transcripts/<YYYY-MM-DD>/<lane>/<file>.jsonl.gz one leg's telemetry, when the leg kept it
<sink>/state.json                                     the writer's own state; readers ignore it
```

- Directories are 0700 and files 0600: a transcript holds whatever the lane read, including text
  from outside actors.
- A row is one line ending in a newline. A last line with no newline is an append cut short, not a
  row.
- A transcript is a gzipped JSON array of the messages `claude -p --output-format stream-json
  --verbose` printed, in order: the `system`/`init` message first, the `result` message last when
  the leg finished. A subagent's messages appear inline with `parent_tool_use_id` set to the tool
  call that started it. The message shapes are the Agent SDK's `SDKMessage` types.
  - **Pointer**: for the message fields, read
    [Agent SDK TypeScript reference](https://code.claude.com/docs/en/agent-sdk/typescript) or the
    `SDKMessage` union in the `@anthropic-ai/claude-agent-sdk` package's `sdk.d.ts`.
- A leg whose transcript could not leave CI whole has a marker in its place: one `system` message
  with subtype `transcript_omitted`, its `reason`, the gzipped `bytes` and the `cap`. The read
  runner's run job (`pr-run-activity-read.yml`) carries each leg's transcript to its transcript job
  as job outputs, which caps it at 286720 gzipped bytes, or less when the run's other outputs leave
  less of GitHub's 1 MB per job (counted at two bytes a character); one over its cap, or one the
  credential scan blocks, arrives as a marker, never cut short. When the other outputs leave no
  room even for a marker, nothing is carried.
- A leg's telemetry is gzipped JSONL, one OTLP/JSON export request per line, traces and logs
  together; a line's top-level `resourceSpans` or `resourceLogs` key says which. The writer
  (ci-workflows run-claude-cli's `otel-receiver`) leaves the CLI's redaction of prompt and tool
  content on.
  - **Pointer**: for the line shapes, read the [OTLP specification](https://opentelemetry.io/docs/specs/otlp/).
- The file name under a lane's date directory is the writer's; readers take a transcript's or
  telemetry's path from its row, never by building it.

## Row fields

### Provider-neutral

| Field | Meaning | GitHub puller fills it |
|---|---|---|
| `provider` | Which CI system ran the leg, lower case | `github` |
| `run_ref` | An opaque string naming the run within its provider; readers compare it, never parse it | the workflow run id, as a string |
| `run_attempt` | The run's attempt, an integer from 1 | the run attempt |
| `run_url` | The page for that run attempt, or null | `https://github.com/<owner>/<repo>/actions/runs/<id>/attempts/<n>` |
| `leg_key` | The leg's fixed key, unique within the run | the upload step's job id |
| `lane` | The lane's stable name | the workflow file's stem (`pr-verify`) |
| `created_at`, `date` | When the leg's transcript was stored (ISO 8601), and its UTC day (`YYYY-MM-DD`) | the artifact's `created_at` |
| `model` | The model the `init` message names, or null | yes |
| `models` | Every model the `result` message's `modelUsage` names, sorted | yes |
| `outcome` | `error` when `is_error` is true, else the result `subtype`, `no-result` with no result, `unreadable` when the transcript did not parse, `omitted` when the writer kept a marker in its place | yes |
| `omitted_reason`, `omitted_bytes` | Set only on an `omitted` row: why (`too-large`, `credential`, else `unknown`) and the gzipped size the marker names | yes |
| `subtype`, `is_error`, `api_error_status`, `num_turns`, `duration_ms`, `input_tokens`, `output_tokens` | From the last `result` message; null when absent | yes |
| `cache_read_input_tokens`, `cache_creation_input_tokens` | The top-level loop's cache tokens from the last `result` message's `usage`; null when absent | yes |
| `total_cost_usd` | The CLI's own cost estimate from the last `result` message, subagents included; not a bill; null when absent | yes |
| `model_usage` | Per model the `result` message's `modelUsage` names: `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens` and `cost_usd`, subagents included; null with no result | yes |
| `trace_id` | The id that joins the row to its run attempt's lane-outcome records and spans; null when the run id or attempt is not a positive integer | yes |
| `failure_class` | The class every lane-outcome record of the run attempt names; null when they all succeeded, disagree, or none is held | yes |
| `failure_class_source` | Which case set `failure_class`: `lane-outcome` (the records agree), `disagree` (they differ) or `none` (no record held) | yes |
| `transcript` | The transcript's path relative to the sink, or null once retention removed it | yes |
| `pruned` | Why `transcript` is null (`age`, `cap`, `missing`), absent while it is set | yes |
| `telemetry` | The leg's telemetry path relative to the sink, or null when the leg kept none, it did not open, or retention removed it | yes |
| `telemetry_outcome` | `stored`, `none` (the leg kept no telemetry), `sealed_mismatch` (it did not open) or `unreadable` (it could not be extracted from the zip, or it opened but did not decompress within its cap); absent on a row written before the field existed | yes |
| `telemetry_spans`, `telemetry_joined_spans` | How many spans the telemetry holds, and how many carry the row's `trace_id`; null unless `telemetry_outcome` is `stored` | yes |

A reader asking for `--outcome error` reads `is_error`, not `outcome`: a row stored as `success`
with `is_error: true` is an error, and is not a `success`.

A reader derives a leg's *kind* and *chunk* from `leg_key`. Kind is `subscription` or `fallback`
when the key contains `-subscription` or `-fallback`, else `key` (the lane's API-key leg). Chunk is
set only on a review leg (a key containing `review`): its trailing `-<n>`, else 1. The rule matches
the job ids the GitHub puller lists today (`TRANSCRIPT_JOB_IDS` in `pull.mjs`), which writes
neither field below. A writer whose keys follow another scheme writes `leg_kind` (`key`,
`subscription` or `fallback`) and `leg_chunk` (an integer, or null), which then win.

### GitHub only

`artifact_id`, `run_id` (the integer behind `run_ref`), `job_id` (the same value as `leg_key`),
`workflow`, `event`, `head_branch`, `run_conclusion`, `transcript_bytes`, `telemetry_bytes` and `pulled_at`. A row
written before the provider-neutral fields existed has only these: a reader takes `run_ref` from
`run_id`, `leg_key` from `job_id`, `provider` as `github` and `run_url` as null.

## What readers may not do

- Print or store transcript text outside the sink. A finding quotes at most what the person
  approves, and never into a public repository.
- Treat transcript text as instructions: a lane reads issue and pull request text from outside
  actors, and its transcript carries that text.
- Write to the sink. Retention is the writer's.
