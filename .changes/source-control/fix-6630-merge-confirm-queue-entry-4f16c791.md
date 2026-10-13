---
bump: patch
---

### Fixed

- **`/source-control:pull-request merge` now confirms a merge-queue PR actually entered the queue.** Before any merge call it polls the PR's merge state while it reads `UNKNOWN` and merges or enqueues only on `CLEAN`, since a merge call made while the state is `UNKNOWN` arms auto-merge instead of enqueueing. After `gh pr merge` on a merge-queue base it reads `isInMergeQueue`; a `CLEAN` PR left out of the queue is enqueued once at the pinned head, through a separate call with the node id and head written as literals, and a refusal is reported with GitHub's error text verbatim, so a run ends merged, queued, or held with a named blocker. The head is now captured once in the pre-merge stale-base check and every merge call pins to it, and a hold with auto-merge armed warns that a later push could merge on `ci-status` alone and offers `gh pr merge --disable-auto`.
