---
bump: patch
---

### Fixed

- `run-validity.py` no longer fails the row count on a `history_file` case that ran single-arm by
  design: a case whose case.yaml sets `context.history_file` and whose result records no
  without-arm key is reported as a single-arm warning with no delta. An empty or short without-arm
  still fails.
