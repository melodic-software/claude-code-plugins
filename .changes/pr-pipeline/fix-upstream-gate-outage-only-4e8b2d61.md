---
bump: patch
---

### Fixed

- The upstream-status gate skips a lane run only while GitHub Actions or npm Package installation
  lists `partial_outage` or `major_outage`. `degraded_performance` and `under_maintenance` now run.
- A hosted review run the gate skips now fails its `kill-switch` job at `Stop on upstream status`,
  and pr-review-main's legs fail the same way, so each is a failed first attempt. The lost-run
  reconciler re-runs a hosted review run's failed jobs once, only for that stop and only while
  the gate would let it run; any other failed or lost review run is still left alone, and a
  main-run review's re-run also waits while the gate would skip it.
- ci-status names a review the upstream gate stopped, and an older run's gate-skip notice, instead
  of reporting a fork or an unlisted bot. For the stop, it asks a person to re-run ci-status once
  the reconciler's review re-run passes, so pr-verify accepts that attempt.
