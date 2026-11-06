---
bump: patch
---

### Fixed

- pr-refine holds a `fix-docs` run whose `fix-docs-head` cannot read the PR head (a failed read, a rate limit past the guard's budget, or an answer with no SHA): the step logs a notice and ends green, nothing else starts but `fix-docs-head-held`, whose `PR head hold` notice monitor signal 13 counts, and the dispatcher counts such a run toward `limits.limit-stops-per-head` as it counts a handoff hold, so the PR is dispatched again. Before, the run ended red. The read runner's report job now reads the PR head a second time after a transient fault, and the shared head read waits a full-jitter 0 to 10 s before that second read.
