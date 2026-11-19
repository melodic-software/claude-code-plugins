---
bump: patch
---

### Fixed

- ci-status's merge-queue verdict reader waits up to 900 s (`WAIT_BUDGET_SECONDS.ciStatusVerify`) for github-token's reset after a read it did not send below the read floor, then judges again, instead of ejecting the lane pull request as `verify:unreadable`; the job's timeout grows to 35 minutes to hold the wait.
