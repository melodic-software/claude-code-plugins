---
bump: patch
---

### Changed

- A clean Write, Edit or NotebookEdit costs the PreToolUse guard row 7 processes on Linux instead of 14. With telemetry off (the default), hardcoded-path-check decides clean content with its builtin prefilter before running `git rev-parse` or `git check-ignore`. secret-pattern-detection opens a capture subshell only when a pattern matched. No verdict changes.
