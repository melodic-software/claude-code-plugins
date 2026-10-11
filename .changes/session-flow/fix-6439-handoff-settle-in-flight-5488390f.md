---
bump: patch
---

### Fixed

- `/session-flow:handoff` settles in-flight work before writing the save-point: it waits for a still-running subagent whose result the handoff depends on, hands off independent work recorded in Environment as before, and asks the user to wait, cancel, or record stuck dependent work as in flight, so a late result no longer leaves the file stale.
