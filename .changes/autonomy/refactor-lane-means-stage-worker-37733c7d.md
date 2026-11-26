---
bump: patch
---

### Changed

- **The `drift-delta-sweep` routine runs three checks.** Its definition and the routines catalog
  call the instruction-placement delta, the enforcement-surface delta and the repository drift
  audit "checks", since "lane" now means only a worker that serves one pipeline stage. What the
  sweep runs is unchanged.
