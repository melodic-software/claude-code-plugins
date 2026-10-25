---
bump: patch
---

### Fixed

- The issue lane's report-outcome opens the PR when the only required checks a done run left undone are test runs (a test runner or a test suite by name), which the lane cannot run. The PR body lists each under Not verified as `Deferred to PR CI`; the PR's CI runs the suites and fix-ci repairs or escalates a failure. Any other required check left undone still stops the run.
