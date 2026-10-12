---
bump: patch
---

### Fixed

- `/discipline:sweep-all` batched pass drops a quoted `CLAUDE_CODE_FORK_SUBAGENT` row that no longer matches the live env-vars page and points at the live fork-mode section instead, and no longer restates the concurrent-subagent-limit error string. `/discipline:recheck-against-upstream` fan-out tier points at where plugin variables resolve instead of asserting it.
