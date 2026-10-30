---
bump: patch
---

### Added

- Two eval cases for the `TodoWrite` task-tool branch, `ho-todowrite-renders-list` for `/session-flow:handoff` and `wf-todowrite-tracks-stages` for `/session-flow:workflow`. A run needs `CLAUDE_CODE_ENABLE_TASKS=0` exported, because a case cannot set the session's tool set.

### Fixed

- The `ho-task-tools-recreate-calls` result grader now matches a recreate call whose quotes the trace escapes more than once, so a correct save-point no longer scores 0.
