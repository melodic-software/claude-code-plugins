# Store and report layout

Everything this skill writes lives under `D/audit-sessions/`, where `D` is the plugin data
directory (`${CLAUDE_PLUGIN_DATA}`). Nothing is written into a repository.

```text
D/audit-sessions/
  store/v2/<source>/p-<12 hex>/<session-id>.json   one record per main session of one transcript source
  store/v2/<source>/history/<16 hex>.json          one history-only prompt of that source
  store/v2/diagnostics/<run-date>-<run-id>.json    one record per collect run
  store/v1.quarantine-<date>/                       the old store once carried over, read by nothing
  reports/machine/<stamp>.json, <stamp>.md          --scope machine (the default)
  reports/<state-key>/<stamp>.json, <stamp>.md      --scope project
  correction-verdicts.json                          the correction lens's verdicts, deleted once merged
```

## Store

- **One store, partitioned by transcript source.** `collect.py` reads every project of each source
  the sources file lists (with none, the local configuration directory, `CLAUDE_CONFIG_DIR` or
  `~/.claude`, as the source `local`), so the store is not keyed by the checkout that ran it.
  `<source>` is the source's configured name. Each record names its own redacted working directory
  and repository identity; `p-<12 hex>` is a hash of the project directory name, which itself is
  not stored because it encodes the working directory unredacted.
- **Provenance and status.** Each record carries `provenance`: the configured `source` and the
  reading host's own `host`, `platform`, `config_dir` and `cc_version`, except that a source read
  through another platform's drive mount (a `windows` source under WSL's automount root) carries
  its declared platform and a null `cc_version`. Its `status` is `present`; `transcript-gone`
  once the reader's listing of its source no longer finds the transcript; `presumed-gone-unverified`
  while the reader cannot check it (its source sent no listing, or its project directory could not
  be listed) and the session ended longer ago than that source's `cleanupPeriodDays`; and
  `present` again once a listing finds it. A source's `cleanupPeriodDays` is the one its reader
  reports this run, else the last one its diagnostics recorded, else Claude Code's default of 30;
  its diagnostics name which (`cleanup_period_days_basis`: `hello`, `prior-diagnostics` or
  `default`). `carried-over` marks a record carried from the old store, which keeps that status. `--force` re-reads every session and still lists what
  is gone. A collect run's retention prunes only the sources it read.
- **History-only prompts.** A `history.jsonl` prompt whose session has no transcript is stored as
  `history-prompt/v1`: its redacted, `audit_sessions_excerpt_chars`-cut text with each pasted text
  restored from `paste-cache/` first (`pastes` counts those restored and those missing), its
  `session_id`, redacted `project`, `time.start` and `provenance`. Only `sweep.py --excerpts`
  reads them, at machine scope; no report, census, drift or friction figure counts them.
- **Diagnostics.** Each collect run writes a `transcript-run.diagnostics/v1` record: per source its
  timing, files, bytes, counts, drift counts, peak memory, the limits applied and declared missing,
  and every gap with the `retry_argv` that re-collects exactly that source.
- **One JSON file per session, replaced atomically.** Re-collecting a session rewrites its file, so
  a repeated run never double-counts. Collect skips a session whose transcript fingerprint is
  unchanged, unless its record was written by a collector with another `collector_digest`, under
  other excerpt settings, or while redaction was failing closed and now is not (or the reverse); `--force`
  re-ingests it regardless. Lowering `audit_sessions_excerpt_chars` to 0 therefore removes stored
  excerpts, titles and agent names on the next collect.
- **Transcript text kept.** A record stores these strings from the transcript, each redacted before
  it is written:
  - excerpts of your own short typed turns, cut to `audit_sessions_excerpt_chars` characters, and
    the session's custom title, generated title (`link_keys.ai_title`) and agent name; 0 stores
    none of them;
  - the working directory, edited file paths (relative to it when inside it), branch names and PR
    repositories (the main session's in `branches` and `prs`, its subagents' in `branches_sub` and
    `prs_sub`), and the names of slash commands, model-invoked skills and assistant errors;
  - in the `friction` block, per event: the command shape, the call's `tool_use_id` for a denial
    or an approved prompt, and, for a denial, the classifier's category or the first line of the
    hook's message; with `audit_sessions_excerpt_chars` above 0,
    also an excerpt of the call's command line or path, the agent's asking line, or the person's
    reply. `/session-flow:audit-friction` documents the block's fields.

  A string longer than max(4096, 16 × `audit_sessions_excerpt_chars`) characters is skipped rather
  than cut and counted in `redaction.skipped_too_long`. While redaction fails closed, no excerpt,
  title or agent name is stored and edited paths collapse to one `<suppressed>` count. Census
  values that are not identifier-shaped are stored as `<other>`. Every other field
  is a count, a duration, a timestamp, or a name Claude Code writes (models, tools, record types,
  permission modes).
- **Redaction is best-effort pattern matching.** It replaces known secret shapes, email addresses
  and home-directory prefixes, and can miss a secret in a shape it does not know.
- **Retention.** Collect drops a record or history prompt whose session ended more than
  `audit_sessions_retention_days` days ago (0 keeps every record), and never ingests one already
  outside that window; diagnostics records share that retention. When `--retention-days` is not
  given, the option's default (180) rises to the longest source `cleanupPeriodDays`, so no record
  goes before its transcript. A value given is kept, and one shorter than a source's
  `cleanupPeriodDays` warns, since records would go before their transcripts.
- **The old store.** `store/v1/`, whose records carry the previous record schema, is carried over by
  the readers. The source that reads this host's own configuration directory is sent this data
  directory's old store; every other source, the same plugin data directory under its own
  configuration directory. Each reader returns the old records the store does not hold whose
  transcript is gone or older than the window, stored with status `carried-over` and `carried_from`
  (`v1_store`, `assumed_root`, and `root_recorded: false`, since a v1 record never named its
  projects root), once per source and session; retention then prunes the expired ones. The rest
  are rebuilt from their transcripts. The reader counts every other file it finds: unreadable, of
  another schema, of another shape, or in a project it could not list. Once the own source's run
  has no gap, nothing was left uncounted that way, nothing lies beside `sessions/`, and every
  record named for rebuilding is held, the old store is renamed, under the host locks, to
  `store/v1.quarantine-<date>/`; that copy is deleted once its date is older than the retention,
  and one whose date does not parse is left alone with a warning. Another host's old store is only
  read, and its source's diagnostics carry the info line `old store pending local migration` until
  that host runs its own collect. `collect.py migrate --dry-run` reports what a run would carry
  over, rebuild and quarantine by the same rule, assuming each rebuild succeeds, and writes
  nothing.

- **How a session was launched.** `entrypoints` lists every `entrypoint` value the main transcript
  carries, or `["unknown"]` when it carries none; a record written before the field existed reads
  as unknown too. Collect skips a transcript Claude Code set aside as `<session>.orphaned-*.jsonl`
  and counts it in `skipped_orphaned`, so it never becomes a second session. A record an earlier
  collector stored for such a transcript is deleted on the next collect, whether or not the
  transcript still exists and whatever `--session` selects, and counted in `purged_orphaned`.

## Reports

- **Interactive sessions only.** Sweep sets aside a session whose entrypoints are all headless or
  Agent SDK ones (the set is `AUTOMATED_ENTRYPOINTS` in `scripts/census.py`) and reports how many;
  a session with no known entrypoint stays in and is counted as unclassified. The drift check still
  reads every record. A headless run of real work is set aside too.
  - **Pointer**: the transcript key is undocumented; its values match the `app.entrypoint`
    attribute in <https://code.claude.com/docs/en/monitoring-usage#standard-attributes>.
  - **As of**: 2026-10-04
  - **Recheck trigger**: that row adds an SDK entrypoint, or a drift run reports
    `key_path:user:entrypoint` as a lost canary.
- `sweep.py --write-report` writes one JSON and one markdown report per run, named by a UTC stamp
  with microseconds. The newest 20 report pairs per scope are kept. No trend file is written: the
  markdown report names the worst 5 sessions (or linked PRs) per finding, and the JSON report holds every one.
- Project-scope reports are keyed by `lib/state-key.sh`, the marketplace's report-keying rule, so
  two checkouts of one repository never share a report.

## Schema versioning

- Records carry `"schema": "session-record/v2"`, the plugin version that wrote them
  (`collector_version`) and `collector_digest`: SHA-256 over the files that shape a record, CRLF
  read as LF, listed in `COLLECTOR_INPUTS` in `collect.py`. A record without the digest is
  re-ingested once.
- New fields are added within v2, and readers treat a missing field as null.
- A breaking change moves the store to the next `store/v<n>/` and ships a migrator in `collect.py`.
  The store cannot be rebuilt from transcripts after Claude Code has swept them.

## Sweep report

- `sweep.py --format json` prints one envelope: `schema` (`audit-sessions.sweep/v1`, the `SCHEMA`
  constant in `scripts/sweep.py`), `status` (`pass`, `warning` or `error`), `summary`, and `data`,
  which `build_data` in `scripts/sweep.py` builds. Every session over a threshold stays in `data`;
  the markdown report is a rendering of it and is not a contract.
- A finding's `evidence` entries name a session (`session_id`), except the `edits.churn_per_pr`
  finding, whose entries name one path within one linked PR: `repo`, `number`, `path`, `edits`
  and the `sessions` that edited it. Only sessions linking exactly one PR count toward churn, the
  `<suppressed>` and `<too-long>` placeholders count as no path, and no PR review outcome is read.
  Each stored path is joined onto its session's `cwd`, so one file edited from different
  directories counts once and same-named files in different directories stay apart; the evidence
  `path` is therefore the full path, and a consumer keeps churn evidence on the machine.
- The `tools.denials` finding also carries `by_kind`, the denials per kind summed over its
  `evidence` sessions, most first, and `dominant_kind`, the first of them. How the kinds are read:
  that rule's `basis` in `sweep-rules.json`.
- Each `data.metrics` row carries `p90`, this store's p90 of the metric under collect.py's
  `_percentile` rule (null for the machine-wide ratio, a degraded metric, or a metric with no
  values), the rule's `threshold`, and
  `baseline_stale`, true when that p90 exceeds `data.stale_p90_factor` times a non-null threshold
  (the recheck trigger in `sweep-rules.json`). The mark is advisory: it raises no finding and leaves
  the exit code unchanged.
- With `--judged`, `data.judged` holds the correction lens's section: `title` (`Judged (unranked)`),
  `note`, `agreement` (null until an agreement figure on a labeled sample exists), `counts`, and
  `findings`, one per turn judged a correction, each with `"confidence": "judged"`, its `turn_id`,
  `excerpt` and `reason`. These findings never enter `data.findings` or `data.suggestions` and leave
  the exit code unchanged. `--judged` refuses `--write-report`, so a saved report never holds an
  excerpt.
- With `--session`, `data.window` carries `session_ids` (the ids named) and `sessions_not_found`
  (those with no record in the store). Metrics and findings cover only the named sessions, kept
  whatever their class, while each row's `p90` and `baseline_stale` still come from every
  interactive session in scope and window. The machine-wide and per-ticket metrics carry
  `"not_applicable": true` with a null `value`, raise no finding and are listed in
  `data.unchecked`. The drift check still reads every record. `--session` refuses `--write-report`.
- `--tickets '<regex>'` prints a separate envelope, schema `audit-sessions.tickets/v1`: `data`
  holds `pattern`, `span_label`, `unkeyed` (interactive sessions with no match), `scope`, `window`,
  `branch_key` with `--branch`, and `tickets`, one row per key with `sessions` (ids in start order),
  `output_tokens`, `span_s`, `prs` (distinct linked PRs) and `gaps_s`. A gap runs from the latest
  end so far to the next start and is 0 for overlapping sessions. It writes nothing.
- `--pr <n> --repo <owner/repo>` prints a separate envelope, schema `audit-sessions.pr/v1`: `data`
  holds `repo`, `number`, `branch` (the `--branch` value or null), `scope`, `window` (`sessions` is
  every session in scope and window, automated ones included), and `sessions` in start order, each
  with `session_id`, `class`, `start`, `end`, `matched_by` (`pr` or `branch`, suffixed `-sub` when
  only a subagent's transcript shows it; the repository compares case-insensitively), `subagents`
  and `output_tokens`. It writes nothing.
- New fields are added within v1, and a consumer treats a missing field as null and ignores one it
  does not know. Removing or renaming a field, or changing what one means, moves the schema to
  `audit-sessions.sweep/v2`.
- Exit codes: 0 pass, 1 warning (a metric degraded by drift), 2 error, 3 no store under the data
  directory. Exit 3 writes nothing; any other exit writes only what `--write-report` asks for.

## Resumed-context report

- `resumed_context.py` reads transcripts, not the store, and writes nothing. Its JSON envelope has
  schema `audit-sessions.resumed-context/v1` (the `SCHEMA` constant in
  `scripts/resumed_context.py`), with `status`, `summary` and `data`.
- `data.sessions` holds one row per resumed session in scope: `session_id`, `project`, `start`,
  `cwd`, `entrypoints`, `handoff` and `handoff_path`, `plugin_version`, `plugin_versions_seen` and
  `ctx_msg10` (null when the session never reached the 10th message).
- `data.counts` holds `transcripts`, `in_scope`, `unattributed`, `automated_set_aside`, `resumed`,
  `reached_10` and `unreadable`. `data.overall` and each `data.groups` row hold `n` and `median`;
  a group also holds `plugin_version` and `sufficient`. With `--baseline` and `--candidate`,
  `data.comparison` holds `baseline`, `candidate`, `rise` and `miss_count`, which the script
  always leaves null.
- Versioning follows the sweep report's rule: new fields within v1, and a removed, renamed or
  redefined field moves the schema to v2. Exit codes: 0 pass, 1 a compared side is short of
  `--min-per-side`, 2 error.
