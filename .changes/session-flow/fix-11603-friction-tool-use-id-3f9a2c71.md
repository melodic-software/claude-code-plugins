---
bump: patch
---

### Fixed

- **Friction events for one tool call count once.** Each `denied` and `prompt-approved` event the audit-sessions collector stores now carries the call's `tool_use_id`. A session keeps one such event per call and kind, so a repeated result record no longer adds a second event to the counts or the shape tally. The friction block counts the skipped records in `duplicates_dropped`, and `/session-flow:audit-friction`'s `mine` reports their total, so you can trace where the repeats come from.
