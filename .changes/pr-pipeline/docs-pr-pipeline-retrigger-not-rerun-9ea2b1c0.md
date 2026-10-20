---
bump: patch
---

### Changed

- The PR pipeline convention says that after main changes a lane workflow, a lane run is
  re-triggered with a fresh event, not `gh run rerun`, which the token broker denies as
  `workflow-modified`.
