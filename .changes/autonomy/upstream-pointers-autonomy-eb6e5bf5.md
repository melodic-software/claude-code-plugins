---
bump: patch
---

### Fixed

- The prerequisite-resolution contract, its setup slice and the setup skill no longer say that `AGENTS.md` reaches a session only through an import when a `CLAUDE.md` is present. Which instruction files a session loads is now a pointer record in the slice context, anchored to the live memory page sections.

### Changed

- Upstream Claude Code specifics restated in the setup and check skills, the agent-session telemetry records, the trigger-dispatch slice, the CI OTLP template, the telemetry, escalation and isolation-ladder references, the README and the lane-stop-gate comments are replaced with pointer records (section anchor, as-of date, recheck trigger). The vendor-neutral references point at new records in the guardrail slice context, and the lane-stop-gate comments point at the README.
