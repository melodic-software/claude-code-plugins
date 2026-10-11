---
bump: patch
---

### Fixed

- `/evals:plugin-eval` references no longer say a `Write` or `Edit` grant needs a sandbox backend; which grants run sandboxed is now read live from the plugin-evals Grant tools section.

### Changed

- `/evals:plugin-eval` and `/evals:methodology` references point at the exact upstream sections (prompt.md fields, grader targets, exit codes and options, JSON result, requirements, and the platform evaluation sections) with an as-of date and recheck trigger instead of restating their defaults, bounds and exit-code meanings.
