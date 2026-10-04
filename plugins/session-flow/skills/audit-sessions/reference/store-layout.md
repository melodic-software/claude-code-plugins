# Store and report layout

Everything this skill writes lives under `D/audit-sessions/`, where `D` is the plugin data
directory (`${CLAUDE_PLUGIN_DATA}`). Nothing is written into a repository.

```text
D/audit-sessions/
  store/v1/sessions/p-<12 hex>/<session-id>.json   one record per main session
  reports/machine/<stamp>.json, <stamp>.md          --scope machine (the default)
  reports/machine/history.jsonl
  reports/<state-key>/<stamp>.json, <stamp>.md      --scope project
  reports/<state-key>/history.jsonl
```

## Store

- **One store per machine.** `collect.py` reads every project under `~/.claude/projects`, so the
  store is not keyed by the checkout that ran it. Each record names its own redacted working
  directory and repository identity; `p-<12 hex>` is a hash of the project directory name, which
  itself is not stored because it encodes the working directory unredacted.
- **One JSON file per session, replaced atomically.** Re-collecting a session rewrites its file, so
  a repeated run never double-counts. Collect skips a session whose transcript fingerprint is
  unchanged, unless its record was written by another plugin version, under other excerpt
  settings, or while redaction was failing closed and now is not (or the reverse); `--force`
  re-ingests it regardless. Lowering `audit_sessions_excerpt_chars` to 0 therefore removes stored
  excerpts, titles and agent names on the next collect.
- **Transcript text kept.** A record stores these strings from the transcript, each redacted before
  it is written:
  - excerpts of your own short typed turns, cut to `audit_sessions_excerpt_chars` characters, and
    the session's custom title and agent name; 0 stores none of the three;
  - the working directory, edited file paths (relative to it when inside it), branch names, PR
    repositories, and the names of slash commands, model-invoked skills and assistant errors.

  A string longer than max(4096, 16 × `audit_sessions_excerpt_chars`) characters is skipped rather
  than cut and counted in `redaction.skipped_too_long`. While redaction fails closed, no excerpt,
  title or agent name is stored and edited paths collapse to one `<suppressed>` count. Census
  values that are not identifier-shaped are stored as `<other>`. Every other field
  is a count, a duration, a timestamp, or a name Claude Code writes (models, tools, record types,
  permission modes).
- **Redaction is best-effort pattern matching.** It replaces known secret shapes, email addresses
  and home-directory prefixes, and can miss a secret in a shape it does not know.
- **Retention.** Collect drops a record whose session ended more than
  `audit_sessions_retention_days` days ago (0 keeps every record), and never ingests one already
  outside that window.

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
  with microseconds, and appends one line to that scope's `history.jsonl`: the stamp, scope, session
  count and each metric's value. The newest 20 report pairs per scope are kept; `history.jsonl` is
  never trimmed, so trends survive pruning.
- Project-scope reports are keyed by `lib/state-key.sh`, the marketplace's report-keying rule, so
  two checkouts of one repository never share a report.

## Schema versioning

- Records carry `"schema": "session-record/v1"` and the plugin version that wrote them.
- New fields are added within v1, and readers treat a missing field as null.
- A breaking change moves the store to `store/v2/` and ships a v1-to-v2 migrator in `collect.py`.
  The store cannot be rebuilt from transcripts after Claude Code has swept them.
