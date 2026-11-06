---
bump: patch
---

### Fixed

- gate migrate's built-in plugin read on harness-ops

  The cc-plugin-agents-md facts come from /harness-ops:inventory when
  the harness-ops plugin is installed; without it they are reported as
  unverified.
