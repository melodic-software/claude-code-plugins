---
bump: minor
---

### Added

- `observer_min_lines` (default 300) skips the observer's post-session analysis for a session with fewer transcript lines, such as an automated sweep. The skip goes to the observer's status file and log, and no ledger is written. `0` analyzes every session.
- The observer writes each analysis run's reported token usage, plus `duration_ms` and `total_cost_usd` when present, to the `analysis` key of its status file and to one log line, so observer spend can be measured per session.
