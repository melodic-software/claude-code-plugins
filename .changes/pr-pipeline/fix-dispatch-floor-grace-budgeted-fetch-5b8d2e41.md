---
bump: patch
---

### Fixed

- The PR-pipeline dispatchers now honor their 10-minute stop-floor grace on the paths that run. `budgetedFetch` and `retryServerErrors` take `floorGraceMs` and hand it to the rate guard, and `feedback-dispatch.mjs` and `dispatch.mjs` pass `DISPATCH_FLOOR_GRACE_MS`. Before, the grace sat only on a default fetch both mains replaced, so a dispatcher failed at the floor with the reset minutes away.
