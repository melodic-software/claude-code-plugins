---
bump: patch
---

### Changed

- ci-status no longer fails red while a review lane is still running on a full run. Its review-lanes
  step polls each waiting lane once a minute, for up to 8 minutes, then judges both lanes as before.
  A review still running at the cap fails as before, with a message saying pr-feedback-dispatch
  re-runs ci-status and no manual re-run is needed. `rerun-ci-status` now leaves alone a ci-status
  that passed with its review step ending after both lanes finished.
