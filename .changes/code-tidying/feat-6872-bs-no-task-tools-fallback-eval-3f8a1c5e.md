---
bump: patch
---

### Added

- An eval case, `bs-no-task-tools-fallback`, runs `batch-simplify` in a session without `TaskCreate`, `TaskUpdate` and `TaskList`, so the skill's no-task-tools path is exercised. It passes only when the run completes, no task tool is called and the files are simplified ([#6872](https://github.com/melodic-software/claude-code-plugins/issues/6872)).
