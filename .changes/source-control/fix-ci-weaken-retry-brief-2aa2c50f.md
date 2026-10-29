---
bump: patch
---

### Fixed

- `pull-request ci --ci` documents the fresh fixer round after a refused weakening: when the
  context file holds the runner's `retry` brief, the fixer looks for a fix in the code under test
  that keeps every test's assertions and expected values, and escalates `weaken-required` again
  when there is none. The never-weaken list is unchanged.
