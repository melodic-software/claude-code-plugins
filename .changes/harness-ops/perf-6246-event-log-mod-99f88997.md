---
bump: minor
---

### Changed

- **The per-session hook event log is a mod (#6246).** The 29 settings rows that ran `session-event-log.sh` and `session-retention.sh` (one per observed event, plus `SessionEnd` retention) started `node` on every fire even with `session_event_log_enabled` off. The new hooks module `hooks/register.ts` hooks those events only while the log is on, so an off install starts no process on any event; on, each event starts one process, which hands the payload to the same script, so the records do not change. The log now needs Claude Code 2.1.287 or later with mods on, does not run where `sec-default` holds `classic.*` events, and writes no `traceparent` key; ADR 0058 records the decision.
