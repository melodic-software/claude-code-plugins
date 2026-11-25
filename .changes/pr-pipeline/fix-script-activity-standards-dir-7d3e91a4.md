---
bump: patch
---

### Fixed

- The write runner's script activity step passes the standards checkout (`STANDARDS_DIR`), so the scripts that read the base config through resolve-config (`report-outcome.mjs`, `declare-test-scope.mjs`) load the vocabulary instead of failing work-resolve-issue's Report Outcome job with `the vocabulary is missing or does not have its expected shape`.
