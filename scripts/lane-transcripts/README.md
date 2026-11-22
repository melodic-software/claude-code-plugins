# lane-transcripts

The transcript puller. CI keeps each lane leg's transcript for 7 days as a sealed artifact
([`upload-lane-transcript`](../../.github/actions/upload-lane-transcript/README.md)); this copies
them to a private sink outside CI, opens them with the private key, and keeps the sink's retention.
It runs four times a night on the laptop. Needs Node 22 or later, `gh` signed in, and `unzip`.

```bash
vault-exec --env LANE_TRANSCRIPT_PRIVATE_KEY=lane-transcript-private-key -- node scripts/lane-transcripts/pull.mjs pull
vault-exec --env LANE_TRANSCRIPT_PRIVATE_KEY=lane-transcript-private-key -- node scripts/lane-transcripts/pull.mjs pull --run RUN_ID
node scripts/lane-transcripts/pull.mjs status
node scripts/lane-transcripts/pull.mjs query --lane pr-verify --model opus --outcome success --since 2026-11-01
node scripts/lane-transcripts/pull.mjs prune
node scripts/lane-transcripts/pull.mjs pull-outcomes
node scripts/lane-transcripts/pull.mjs backfill
```

| Command | Does | Exit |
|---|---|---|
| `pull` | Copies every new `lane-transcript-*` artifact, then prunes | 0 done, including one that missed an artifact; 1 failed, and `ALERT:` on stderr when no pull succeeded in 5 days (a pull that missed an artifact and is that stale exits 1 too), or when a budget-stopped backlog is over 5 days old. A stale `pull-outcomes` prints its `ALERT:` here too but does not change this exit code, so a timer that chains the two still reaches it |
| `pull --run RUN-ID` | Copies that one workflow run's `lane-transcript-*` artifacts, listed from the run itself, with the same checks and rows as `pull`; writes no pull state and prunes nothing, so the scheduled pull's cursors and resume point stay as they were | 0 done; 1 when an artifact was missed or the run's listing failed |
| `status` | Prints the last successful pull, its age, and the store's size and counts as JSON | 1 and `ALERT:` when no pull succeeded in 5 days, or a budget-stopped backlog is over 5 days old; the same two checks apply to `pull-outcomes` once it has run |
| `query` | Prints the metrics rows matching every filter given, as JSONL with the transcript's absolute path | 0 |
| `prune` | Applies retention alone | 0 |
| `pull-outcomes` | Copies the lane-outcome records of every lane workflow run to `outcomes.jsonl`, then sets each row's failure class | 0 done, including one that missed a run; 1 failed |
| `backfill` | Fills `trace_id`, the failure class, and the cache, cost and `model_usage` fields on rows written before them; idempotent | 0 |

`query` filters: `--lane` (the workflow file's stem, or `lane/job-id`), `--model` (a substring of
any model the leg used), `--outcome`, `--class` (a failure class), `--trace` (a trace id),
`--since` and `--until` (`YYYY-MM-DD`, inclusive). For
anything else, read `metrics.jsonl` with `jq`. No command prints transcript text.

`--outcome` takes `error` (every leg whose result has `is_error: true`), `success` (a `success`
subtype on a leg that did not error), another result `subtype` such as `error_max_turns`, or
`no-result`. It reads `is_error`, so a row stored with `outcome: success` and `is_error: true`
answers to `error`; the printed row keeps the values it was stored with.

## The sink

One value names it: `--sink DIR`, else `LANE_TRANSCRIPT_SINK`, else
`$XDG_DATA_HOME/lane-transcripts` (`~/.local/share/lane-transcripts`). Another sink, such as another
machine or object storage, is any directory it mounts at; nothing else changes. Directories are
0700 and files 0600.

```text
<sink>/transcripts/<YYYY-MM-DD>/<lane>/<run id>-<attempt>-<job id>.json.gz   the CLI messages, gzipped
<sink>/transcripts/<YYYY-MM-DD>/<lane>/<run id>-<attempt>-<job id>.otel.jsonl.gz   the leg's telemetry, gzipped
<sink>/metrics.jsonl                                                       one row per transcript, no content
<sink>/outcomes.jsonl                                                      one row per lane-outcome record
<sink>/state.json                                                          last success, last attempt, last error kind, each name's cursor
```

The layout and every row field readers rely on are the
[lane-transcripts contract](../../docs/contracts/lane-transcripts/README.md), which names the
provider-neutral fields this puller fills (`provider`, `run_ref`, `run_url`, `leg_key`). A
metrics row also holds the artifact, run, attempt and job ids, lane, workflow name, event, branch,
the run's conclusion when pulled, `created_at` and `date`, the init message's `model`, the result
message's `models` (its `modelUsage` keys), `outcome` (`error` when `is_error` is true, else the
`subtype`; `omitted`, with `omitted_reason` and `omitted_bytes`, for a writer's marker), `subtype`, `is_error`, `api_error_status` (`null` when the result carries none),
`num_turns`, `duration_ms` and token counts, the transcript's size, and its path (`null` once
pruned).

From the result message a row also keeps `cache_read_input_tokens` and
`cache_creation_input_tokens` (the top-level loop's `usage`, as `input_tokens` is),
`total_cost_usd`, and `model_usage`: per model in `modelUsage`, its input, output, cache-read and
cache-creation tokens and `cost_usd`. `total_cost_usd` and `model_usage` count subagents too. The
cost fields store the CLI's own estimate, not what was billed; on a subscription leg it measures
the work, not spend ([track your costs](https://code.claude.com/docs/en/costs#track-your-costs)).
A leg that crashed can report zeros. Issue #7676 left cost and tokens as published per-run fields
to other issues; the owner's observability decision covers keeping them in this private sink.

`trace_id` is the first 32 hex digits of SHA-256 over `lane-outcome:<run id>:<attempt>`, the trace
id every lane-outcome record of that run attempt carries (ci-workflows `docs/lane-outcome.md`,
"Run context"), so a row joins its records, and any span exported under that trace, by run
attempt. `failure_class` comes from those records, never from the transcript. When a record's
`jobId` equals the row's `job_id`, only the records with that `jobId` count. Otherwise only the
records with no `jobId` count: an older record names its lane and credential but not the leg's
job-id, so it counts for every leg of the attempt. The class is set when every counted record names
the same class (null when they all succeeded), and null otherwise. `failure_class_source` says which
held: `lane-outcome`, `disagree` (the counted records differ), or `none` (no record counted yet).
A row pulled before its records is set by the next `pull-outcomes` or `backfill`. The `lane_runs` and `lane_outcomes` DuckDB views in
`plugins/harness-ops/skills/observability/otel/lane-runs.sql` read both files.

## What a pull takes

Artifacts are listed one name at a time, since the repository-wide artifact listing answers 500
for this repository. A name is `lane-transcript-<job-id>-<attempt>`: `TRANSCRIPT_JOB_IDS` in
`pull.mjs` holds every job-id an upload step passes, by workflow, including the `ci-workflows`
reusables this repository calls with the transcript key, and the pull lists each with attempts 1
to 3. `pull.test.mjs` fails when a workflow that calls `upload-lane-transcript`, uploads a
`lane-transcript-` artifact itself, or calls such a reusable is missing from that list, or a local
job-id is (an expression in it matches any text; the read runner's activities are checked against
its callers),
so a new upload step adds its job-id there, and a job-id holds no value a fixed list cannot name,
such as an issue number; a job-id that changes inside a reusable is not checked.

Each pull first lists the newest 100 runs of every workflow in `RUN_WORKFLOWS`, the workflows
whose runs upload transcripts (a reusable's callers stand in for it, `TRANSCRIPT_CALLERS`), with
no `created` filter, so a re-run of an older run still shows. Attempt 1 of every name is listed
on every pull; attempt 2 or 3 only when one of its workflows' listed runs reached that attempt, or
when the name was last listed through more than a day ago, which catches a re-run past those 100
runs. A workflow whose run listing fails has all its attempts listed. A pulled artifact's run
details come from that listing, or from one run read when its run is not in it.

Each name is listed newest first, back to its own cursor less 6 hours, by the artifact's own
`created_at`, so a re-run attempt of an older run is still pulled. The cursor (`cursors` in
`state.json`) is when the name was last listed through with every artifact handled; a name stopped
inside by the budget, or with an artifact that failed, keeps its old one. A name with no cursor
lists back to the last successful pull less 6 hours, or a budget-stopped pull's kept cutoff (7
days on the first pull). It skips an artifact it already holds, an expired one, one over 64 MiB, and one whose
run's head repository is not this repository: the public key is public, so a fork's run could seal
a record. A zip must hold `transcript.json.gz.sealed` and at most one other entry, which must be
a sealed file (`<name>.sealed`); any other zip counts as `bad_zip`. A transcript record that does
not open for the key, the artifact's run id and its job id (moved, tampered with, or sealed under a
rotated key) is counted as `sealed_mismatch` and skipped. The summary line counts each kind.

When the other entry is `otel.jsonl.gz.sealed` (`upload-lane-transcript`'s `otel-file`), the pull
opens it under the payload name `otel.jsonl.gz` with the same run and job binding and stores it
beside the transcript. The row's `telemetry_outcome` says what happened (`stored`, `none`,
`sealed_mismatch`, `unreadable`); a telemetry record that does not open keeps the transcript.
`telemetry_spans` counts the spans and `telemetry_joined_spans` those whose `traceId` is the row's
`trace_id`, so a row shows whether the leg's spans joined its run attempt.

A `gh` call that fails is retried, the wait doubling from 2 seconds: a listing page gets 10 tries with the wait capped at 5 minutes, any other call 5 tries. An artifact whose download,
unzip or run read still fails counts as `fetch_failed` and the pull goes on. It has no metrics row
and the last success stays where it was, so the next pull lists back far enough to fetch it. The
last success is therefore the last complete pull: an artifact that keeps failing holds it until
the artifact expires at 7 days, and the 5-day alert can fire first. `last_error` names the count
and the calls that failed (`artifact-zip`, `artifact-unzip`, `run-read`).

Three outcomes fail the pull and leave the last success where it was, so the 5-day alert can fire:
a rate limit on any `gh` call, which is not retried (`rate-limited`), a listing page that still
fails after its tries (`artifact-list`, since skipping it would lose artifacts for good), and a
window where records failed to open and none opened or was already held (`key-mismatch`: the vault
key and the repository variable differ).

A pull makes at most `GH_CALL_BUDGET` (1,000) `gh` calls, retries included, so one run cannot
spend the login's shared hourly budget. At the budget it stops fetching, keeps what it has, and
records a success with `budget_exhausted: true`, the oldest cutoff any name will list back to as
`resume_cutoff_at`, and the name it stopped on as `resume_name`; the next pull starts at that name
and wraps round, so no name starves, and each name lists back to its own cursor. When that kept
cutoff is more than 5 days old, `pull` and
`status` alert and exit 1 although the last success is fresh, two days before the 7-day listing
floor would pass it and drop the rest. Every pull, failed or not, ends with a
`gh calls: N of 1000` line.

## What `pull-outcomes` takes

It lists the completed runs of each workflow in `LANE_WORKFLOWS` (`pull.mjs`): those that run
`report-lane-outcome` or `run-claude-cli`, a ci-workflows lane reusable, or a local reusable that
does. `pull.test.mjs` fails when that list and the workflows differ. Runs are listed back to its
own last success less 6 hours (30 days on the first run); for each run it reads the jobs of every
attempt and each job's check-run annotations, and keeps every lane-outcome record that
`.github/scripts/lib/lane-outcome.mjs` validates, with only its known fields. It skips a fork's
run, a skipped job, a job it already holds a record from, and a record whose own run id, attempt
or trace id names another run attempt (`mismatched`). It reads annotations only, never the
`report-check-run` check run's copy of the same record. Each `outcomes.jsonl` row holds
`run_id`, `run_attempt`, `trace_id`, `check_run_id`, `job_name`, `lane`, `workflow`,
`created_at` (the job's completion), `date`, `record` and `job_records` (how many records its job
holds; the next pass drops and reads again a job an interrupted pull left with fewer).

It keeps the transcript pull's rules under the state's `outcomes` key, apart from the pull's own:
the same retries and rate-limit stop, a run whose jobs or annotations still fail counts as
`fetch_failed` and holds its last success, and a budget of `OUTCOME_CALL_BUDGET` (1,000) `gh`
calls of its own, stopping with `budget_exhausted`, `resume_cutoff_at` and `resume_workflow` and
resuming at that workflow. It records each run attempt it finished reading as `read_runs`, so a resumed pass skips them at no call, and drops the entries older than its next cutoff. A re-run attempt of a run created before its window is not reached.

## Retention

Every pull, and `prune`, applies it in this order:

1. A transcript over 30 days old is deleted; its row stays, with `transcript: null`. Its
   telemetry goes with it (`telemetry: null`).
2. A metrics row, or a lane-outcome record, over 365 days old is dropped.
3. While every file under the sink totals more than 5 GB (5,000,000,000 bytes), the oldest
   transcript is deleted.

A file no row names ages by its modification time.

## Key setup

The pair is X25519 in the [`seal-lane-output`](../../.github/actions/seal-lane-output/README.md#format)
format. The private key lives in Key Vault `kv-melo-github-prod` as `lane-transcript-private-key`,
which `vault-exec` reads once the dotfiles map `.chezmoidata/vault-secrets.yaml` lists it there.

From the repository root, on WSL (`az` is the Windows binary, so it reads the key file through a
`\\wsl.localhost` path; `$XDG_RUNTIME_DIR` is memory-backed):

```bash
umask 077 && node .github/actions/open-lane-output/keygen.mjs --private-key-fd 3 3>"$XDG_RUNTIME_DIR/lane-transcript.key" >"$XDG_RUNTIME_DIR/lane-transcript.pub" && az keyvault secret set --vault-name kv-melo-github-prod --name lane-transcript-private-key --file "$(wslpath -w "$XDG_RUNTIME_DIR/lane-transcript.key")" -o none && gh variable set LANE_TRANSCRIPT_PUBLIC_KEY -R melodic-software/claude-code-plugins <"$XDG_RUNTIME_DIR/lane-transcript.pub"; rm -f "$XDG_RUNTIME_DIR/lane-transcript.key" "$XDG_RUNTIME_DIR/lane-transcript.pub"
```

The variable is set only after the private key is stored, so CI never seals to a key nobody holds.
`-o none` matters: `az keyvault secret set` otherwise prints the stored value. To rotate, run the
same line; transcripts sealed under the old key count as `sealed_mismatch` until they expire.

## Daily task

A systemd user timer on the laptop, owned by `melodic-software/provisioning`
(`templates/wsl-user-jobs/lane-transcript-pull/`), starts the job at 00:00, 02:00, 04:00 and 06:00
with `Persistent=true`, so a run missed while the WSL distribution was down runs when it next
starts. Each run uses the puller from `origin/main`, not the clone's working tree.

`pull-outcomes` runs after `pull` in the same unit, never beside it: both rewrite `metrics.jsonl`.
It runs whether `pull` succeeded, failed or was skipped, and without the private key. Either step
is skipped when fewer than 2,000 REST calls remain on the `gh` login.

A failed `pull` leaves the unit failed, which `systemctl --user --failed` shows, and raises a
desktop toast. A failed `pull-outcomes` or a skipped step is only logged and leaves the unit
successful. A timer that never fires raises nothing. `status` is the check for a failed
`pull-outcomes`, a skipped step and a timer that never fires.
