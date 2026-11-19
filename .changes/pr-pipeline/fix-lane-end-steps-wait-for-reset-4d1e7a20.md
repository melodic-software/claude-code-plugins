---
bump: patch
---

### Fixed

- work-resolve-issue's steps after the model ran wait for the workflow token's rate-limit reset, up to 1200 s (`rate-limit-wait-seconds`), instead of failing the run: the leak scan's reads, report-outcome and apply-issue-patch, Run Checks and Report Statuses. A stop-floor answer GitHub served no longer fails its step when the next call waits the reset out, and Report Statuses names the lane branch a run left when report-outcome did not finish, which the issue's next run reuses.
