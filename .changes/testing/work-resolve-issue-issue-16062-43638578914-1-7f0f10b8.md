---
bump: patch
---

### Changed

- The `/testing:audit` bash-harness adapter no longer treats a `gate_test::run_suite` call as handing
  off a test's assertions. That runner belongs to one repository. A repository with its own suite
  runner names it under `extend.bash-harness.delegation` in its testing config.
