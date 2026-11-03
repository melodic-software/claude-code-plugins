---
bump: patch
---

### Fixed

- The hourly triage sweep counts a dispatched intake run as an attempt only when its `intake-triage`
  job ran, read from the run's jobs. A run the lanes kill switch or another gate skipped, or that was
  cancelled before intake, no longer uses up an attempt and hands the issue to `needs-triage`; the
  sweep dispatches it again, and 6 dispatches hand it off whatever reached intake. A jobs read that
  fails counts the run, as before.
