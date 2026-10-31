---
bump: patch
---

### Fixed

- The babysit merge gate binds a review lane's second attempt after the upstream-status gate
  stopped the first (class `upstream-degraded`): the caller's `kill-switch` job failed with the
  lane's `an upstream outage stops this review (` error and no lane job ran. A failed
  `kill-switch` job without that error, the error at another level, or the error beside a lane
  job still does not bind.
