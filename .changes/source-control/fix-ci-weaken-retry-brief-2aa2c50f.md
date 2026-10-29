---
bump: patch
---

### Fixed

- `pull-request ci --ci` documents the fresh fixer round after a refused weakening: when the
  context file holds the runner's `retry` brief, the fixer keeps every test's assertions, changes
  an expected value only when the behavior change in `pr_title` or `pr_body` requires it, and
  reports that check as `fixed expectation <reason>`. The never-weaken list is unchanged.
