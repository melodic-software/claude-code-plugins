---
bump: none
---

`.github/scripts/pr-merge/cancel-orphaned-runs.mjs` now cancels only `merge_group` runs on `gh-readonly-queue/main/` branches, the one base whose commits its merged-group guard reads, so a run in another base's queue is never cancelled.
