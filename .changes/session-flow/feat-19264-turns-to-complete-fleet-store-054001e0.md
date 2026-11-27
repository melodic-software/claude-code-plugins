---
bump: minor
---

### Added

- `session_record.py` (`collect.py`) records per-subagent dispatch rows under `subagents.dispatches` (`agent_type`, `date`, `turns`, `last_stop_reason`, `hit_max_turns`, `resumed_after_turn`, `resumed_after_max_turns`) within `session-record/v2`; existing and carried-over records without `subagents.dispatches` remain readable and `collector_digest` triggers one-time re-ingest for present transcripts.
- `scripts/dispatches.py` (`audit-sessions.dispatches/v1`) reads per-dispatch turn rows from the audit-sessions store across every collected source, reporting store gaps, stale sources and stored records lacking per-dispatch rows in `data.header` (exit 0 pass, 2 error, 3 no store).
