---
bump: minor
---

### Changed

- `audit-sessions` markdown report names the worst 5 sessions (or linked PRs) per finding, then how many more there are and that the JSON report holds the full list; the JSON report is unchanged.
- The metrics table gains a `Statistic` column: `cache.write_5m_share` reads "machine-wide ratio" and `hooks.stop_ms` reads "median of per-session p90" instead of "median".
- The `audit-sessions` description and opening no longer claim to audit corrections or trends, and the "why am I correcting Claude so often" and "am I getting faster" triggers are removed; the opening now says to compare two `--since`/`--until` runs by hand.

### Removed

- `sweep.py --write-report` no longer appends to `reports/<scope>/history.jsonl`; nothing read it. Existing files are left in place.
