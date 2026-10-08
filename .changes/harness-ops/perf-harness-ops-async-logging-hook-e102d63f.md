---
bump: patch
---

### Changed

- **The per-session event log runs in the background.** Every `session-event-log.sh` row except SessionEnd's now sets `async: true`, so the log write no longer holds up prompt submission or the other events; the `UserPromptSubmit` row had timed out at 5 seconds on a slow machine. Per the hooks reference ("Run hooks in the background") an async command hook is not awaited and its exit code and output are not read, which suits a row that only records. The SessionEnd row stays synchronous: its hooks share a 1.5-second teardown budget. The audit and telemetry rows are unchanged.
