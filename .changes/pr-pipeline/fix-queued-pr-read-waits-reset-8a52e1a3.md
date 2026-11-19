---
bump: patch
---

### Fixed

- Check Plugins' merge-group read of the queued pull request waits for a rate limit's reset when it is at most `WAIT_BUDGET_SECONDS.queuedPr` (900 s) away, then reads again, instead of failing at once and making the bump, fragment, release and vendor gates refuse and eject the group. The job's timeout rises from 9 to 24 minutes to hold the wait.
