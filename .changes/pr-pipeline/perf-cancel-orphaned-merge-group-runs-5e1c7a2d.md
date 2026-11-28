---
bump: none
---

pr-merge's `dispatch-full-run` job now cancels queued and in-progress `merge_group` runs whose `gh-readonly-queue/` branch the merge queue has deleted, at most 20 per run and only runs older than 60 seconds, through `.github/scripts/pr-merge/cancel-orphaned-runs.mjs`, which the hold floor holds as a `gate` path.
