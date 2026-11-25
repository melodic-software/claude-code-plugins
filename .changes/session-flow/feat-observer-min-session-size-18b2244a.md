---
bump: minor
---

### Added

- `observer_min_lines` (default 300) skips the observer's post-session analysis for a session with fewer transcript lines, such as an automated sweep, until it has a ledger. The skip goes to the observer's status file and log, and no ledger is written. A follow-up to an analyzed session is always analyzed. `0` analyzes every session.
- The observer records each analysis run's reported token usage, plus `duration_ms` and `total_cost_usd` when present, as a timestamped entry in its status file's `analysis_runs` list and one log line, so observer spend can be measured per session.
