---
bump: minor
---

### Added

- pr-verify now gives the verifier `upstream-jobs.json`: the jobs of the pr-require-checks run it
  was started by, each with its name and conclusion, read with each judging job's own token. The
  verifier judges from it whether the suites that cover the changed files ran, as part of its rule
  on tests that do not cover the change, and runs no test or eval itself. The model's tool rules,
  `ci-status` and the verdict path do not change.
