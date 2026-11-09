---
bump: minor
---

### Changed

- In a linked git worktree, the hook log root (`session_event_log_dir`) now sits under the main checkout instead of the worktree. The session event log, the telemetry sink and SessionEnd retention write there, and `/harness-ops:observability` reads there, so a worktree session's rows survive the worktree's removal and a report from the main checkout counts them. SessionEnd retention's `session_log_keep_sessions` now counts the sessions of every worktree together. A directory outside git, a submodule, and a worktree of a bare repository whose directory is not named `.git` keep their own directory.
