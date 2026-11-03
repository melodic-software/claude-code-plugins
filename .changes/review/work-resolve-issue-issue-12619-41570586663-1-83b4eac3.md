---
bump: patch
---

### Changed

- The size-crossing step in `quality-gate` code mode and `fanout` default mode now runs
  `/code-metrics:audit size`, since code-metrics replaced `audit-size` with the `audit` router.
  It still runs only when the code-metrics audit skill is installed.
