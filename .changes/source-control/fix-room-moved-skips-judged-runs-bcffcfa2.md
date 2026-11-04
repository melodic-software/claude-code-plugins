---
bump: patch
---

### Fixed

- The post-merge report now records each full and canary run its run listing read as completed,
  with the `updated_at` it read (`judgedRuns`). `pending_runs_unchanged` and `idle_runs_refusal`
  (the lane room, the merge job's `settle`, the idle tick and `refusal_moved`) no longer count
  such a run as moved when it still reads that `updated_at`: the check already judged it
  finished. Before, a run that completed within the 60-second clock margin before `computedAt`,
  or during the check's reads, read as `runs-moved` and ran the whole post-merge check again. A
  re-run changes `updated_at` and still counts as moved, a run still in progress is handled as
  before, and a report without the field counts every run completed since as moved, as before.
