---
bump: patch
---

### Fixed

- The issue lane's blocker gate counts the same closes admission does: a size-split parent the lanes App closed once a listed human or a merge closed every sub-issue no longer blocks a run admission already let through (`.github/scripts/work-resolve-issue/check-blockers.mjs`, now on `admit.mjs` `closedByTrusted`).
