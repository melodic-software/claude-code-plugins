---
bump: patch
---

### Changed

- The `babysit-prs` engine's unittest suite runs as four shell suites instead of one, so each
  stays under CI's 120 s per-suite budget: `engine-b.test.sh` runs
  `tests/test_babysit_merge_policy.py`, `engine-c.test.sh` the `tests/test_babysit_postmerge*.py`
  modules, `engine-d.test.sh` every other `tests/test_babysit_*.py`, and `engine.test.sh` the
  remaining modules beside its ruff pass and wrapper checks. The new `engine-run.sh` assigns each
  module to exactly one part and fails when a part's wrapper is missing. No test was added or removed.
