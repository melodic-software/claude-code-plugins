---
bump: none
---

pr-merge's `dispatch-full-run` job now cancels queued and in-progress `merge_group` runs whose `gh-readonly-queue/` branch the merge queue has deleted, at most 20 per run, only runs older than 60 seconds and never a run whose head commit is in main's last 100 commits (a merged group), through `.github/scripts/pr-merge/cancel-orphaned-runs.mjs`, which the hold floor holds as a `gate` path.
