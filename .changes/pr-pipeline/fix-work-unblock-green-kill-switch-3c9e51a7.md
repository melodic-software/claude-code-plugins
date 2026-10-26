---
bump: patch
---

### Fixed

- work-unblock counts a run whose broker-check `Check the kill switch` step saw a kill switch on, and so skipped the broker ask, as a breaker trip. That run ends green with no failed step, so it was handed to a person as stranded with no report instead of being re-fired. The jobs listing alone shows it; no log is read (`.github/scripts/work-unblock/label-unblocked.mjs`).
