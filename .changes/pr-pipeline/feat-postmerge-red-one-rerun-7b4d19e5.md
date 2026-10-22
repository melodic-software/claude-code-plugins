---
bump: patch
---

### Fixed

- pr-merge's `post-merge-dispatch` job re-runs a red full run it dispatched once before the
  demotion alert judges it, when the run is under 90 minutes old and demotes by the affected-set
  rule, not only inside a lane merge's attribution window. The alert demotes only when that
  re-run fails too.
