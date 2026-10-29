---
bump: patch
---

### Fixed

- A pr-review-main run whose first attempt failed before any lane's verdict write started (every
  credential leg stopped) is now re-run once, recorded, by the lost-run reconciler, as a lost
  pr-verify run is, so a lane-source pull request no longer waits for its next push to be
  reviewed from main.
