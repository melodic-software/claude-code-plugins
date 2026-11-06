---
bump: patch
---

### Fixed

- gate pressure-test's performance hand-off

  A performance-target fork hands off to /performance:goal only when the
  performance plugin is installed; otherwise the timing is recorded as
  unqualified and the user is asked.
