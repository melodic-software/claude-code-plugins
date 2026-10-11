---
bump: patch
---

### Fixed

- **`/source-control:pull-request merge` now confirms a merge-queue PR actually entered the queue.** After `gh pr merge` on a merge-queue base it reads `isInMergeQueue`; a `CLEAN` PR left out of the queue is enqueued once at the pinned head, and a refusal is reported with GitHub's error text verbatim, so a run ends merged, queued, or held with a named blocker.
