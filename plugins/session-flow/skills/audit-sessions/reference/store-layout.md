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
  store is not keyed by the checkout that ran it. Each record names its own project directory,
  working directory and repository identity; `p-<12 hex>` is a hash of the project directory name.
- **One JSON file per session, replaced atomically.** Re-collecting a session rewrites its file, so
  a repeated run never double-counts. Collect skips a session whose transcript fingerprint is
  unchanged; `--force` re-ingests it.
- **Transcript text kept.** Only short excerpts of your own typed turns, redacted before they are
  written and capped at `audit_sessions_excerpt_chars` characters (0 stores none). Every other
  stored field is a count, a duration, an identifier or a redacted path.
- **Retention.** Collect drops a record whose session ended more than
  `audit_sessions_retention_days` days ago (0 keeps every record), and never ingests one already
  outside that window.

## Reports

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
