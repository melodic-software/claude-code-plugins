---
bump: patch
---

### Fixed

- The routines contract's `dynamic workflow` row no longer says a workflow is always composed at
  run time: each run is session-scoped, and its script can be saved in the project or a plugin.
  The README says a command hook, not every hook, cannot re-run the `/goal` evaluator, and points
  at the goal and hooks pages (#6916).
