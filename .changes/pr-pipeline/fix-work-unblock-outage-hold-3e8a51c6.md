---
bump: patch
---

### Fixed

- work-unblock's sweep holds through a failed listing instead of failing. A failed closed-issue
  listing prints a notice, does nothing more and ends green, and the next sweep's window stays back,
  so it reads the closes that listing missed: `sweepSince` starts from the last run only when its job
  log shows it read the listing. A failed listing of the deferred, open or `agent-ready` issues holds
  with a notice while the sweep goes on.
