---
bump: patch
---

### Fixed

- The `motion-dialog` eval samples that used the drawer curve for a centered dialog's entrance now
  use the configured `out` curve, `cubic-bezier(0.23, 1, 0.32, 1)`. The graders and each sample's
  pass or fail expectation are unchanged.
