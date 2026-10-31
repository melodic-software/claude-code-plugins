---
bump: patch
---

### Fixed

- The lost-run reconciler now re-runs a hosted review run a kill switch stopped, recorded, once
  neither the lanes switch, the lane's own switch nor the upstream gate would stop it again. Its
  completion re-runs ci-status, so a head a review switch left red clears without a person. One
  lane per head per half-hourly pass, up to GitHub's 30-day re-run window.
