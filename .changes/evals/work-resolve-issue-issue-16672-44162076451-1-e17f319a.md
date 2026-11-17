---
bump: patch
---

### Changed

- `/evals:plugin-eval` states how a registered two-version compare reads a loss at 3 runs a side: below about 20 cases the `compare verdict` interval test does not decide it, a `case drop` starts a trace read of each dropped case and an Opus confirm, and only a loss the trace ties to the changed text counts. `reference/reading-results.md` adds the false-loss figures behind that reading: at 3 cases and 3 runs a side, a version that changed nothing passes `noise-report.py`'s non-inferiority rule about 20% of the time.
