---
bump: patch
---

### Changed

- pr-merge starts at most one full run of main per 30 minutes, of main's tip, covering every merge since the last. dispatch-full-run and post-merge-dispatch read the newest pr-require-checks.yml dispatches on main first (`Read main's full-run cover`): within the cap they start nothing, and post-merge-dispatch starts one on its next scheduled run for a tip no full run covers, whoever merged, while the lane is live (kill switch and report-only off). A read of the cover refused for a rate limit stops the job red and sends nothing more (`.github/workflows/pr-merge.yml`).
- dispatch-full-run ends once it dispatches, where it held a runner up to 39 minutes polling the run; its timeout drops from 45 to 10 minutes. post-merge-dispatch now sends a red full run to post-merge-demotion-alert.yml on its next scheduled run while the lane is live (kill switch and report-only off), up to 15 minutes after the run ends, once per run (`pr-merge-alerted-<id>`), and skips a run that never started.
- pr-require-checks.yml's dispatches on main (attempt 1) share one concurrency group with no `queue` key and `cancel-in-progress` false: one runs, one waits, and a newer one replaces the waiting one. A re-run and every other run keep their own group and cancel.
- post-merge-demotion-alert.yml files nothing for a cancelled full run with no job, one the concurrency group replaced before it started.
