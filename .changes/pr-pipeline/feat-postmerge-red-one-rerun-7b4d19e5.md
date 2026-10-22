---
bump: patch
---

### Fixed

- pr-merge's `post-merge-dispatch` job re-runs a red full run it dispatched once before the
  demotion alert judges it, when the run was created within `red-main.confirm-wait-minutes` plus
  50 minutes (90 by default) and demotes by the affected-set rule, not only inside a lane merge's
  attribution window. The alert demotes only when that re-run fails too.
