---
bump: patch
---

### Added

- Two eval cases for the `TodoWrite` task-tool branch, `ho-todowrite-renders-list` for `/session-flow:handoff` and `wf-todowrite-tracks-stages` for `/session-flow:workflow`. A run needs `CLAUDE_CODE_ENABLE_TASKS=0` exported, because a case cannot set the session's tool set.
