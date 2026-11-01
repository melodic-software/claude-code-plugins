---
bump: patch
---

### Fixed

- The `acr-dir-batch-skips` eval's `markdown-skipped` grader now anchors at the start of the answer with `(?<![\s\S])` instead of `\A`. JavaScript, which runs the grader, reads `\A` as a literal `A`, so `/evals:validate` reported a FAIL for the case.
