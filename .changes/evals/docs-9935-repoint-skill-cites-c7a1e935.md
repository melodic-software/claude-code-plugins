---
bump: patch
---

### Fixed

- `/evals:plugin-eval` says what an unset `grader_run_twice` setting means where it decides whether to pass `--grader-agreement`: an unexpanded, empty or other value means `true`, the manifest default, so an unset key no longer reads as neither true nor false.
