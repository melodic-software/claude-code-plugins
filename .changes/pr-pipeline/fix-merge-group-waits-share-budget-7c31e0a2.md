---
bump: patch
---

### Fixed

- A merge group's two waits for a pool's reset share one budget, `WAIT_BUDGET_SECONDS.mergeGroup` (600 s), in place of 900 s each: Check Plugins' queued pull request read waits first, and ci-status's verdict reader waits only what that left, so both cannot run the group past the merge queue's 30-minute check timeout and eject it. With nothing left, the reader's `verify:unreadable` stands. Check Plugins' timeout drops to 19 minutes and ci-status's to 30.
