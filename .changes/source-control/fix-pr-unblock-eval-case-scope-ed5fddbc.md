---
bump: patch
---

### Fixed

- The `comments --ci` review-thread tool's `check-paths` and `record` now also allow any file in the `plugins/<p>/evals/<case>/` directory a kept thread's path sits in, and a test file (`test_*.py`, `*_test.py`, `*.test.*`, `*.spec.*`) in the same directory as a kept thread's path. `.github/` stays refused.
