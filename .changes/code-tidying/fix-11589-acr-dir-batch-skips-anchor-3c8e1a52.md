---
bump: patch
---

### Fixed

- The `acr-dir-batch-skips` eval case's `markdown-skipped` grader opened with Python's `\A`, which
  the JavaScript engine that runs it reads as a literal `A`. It now opens with `(?<![\s\S])`, a
  start-of-input anchor in both engines, so every sample passes or fails as it states.
