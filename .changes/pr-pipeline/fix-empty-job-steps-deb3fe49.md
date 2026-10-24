---
bump: patch
---

### Fixed

- pr-merge's refire step now reads the annotations of a failed pr-unblock write-runner job (`<caller> / run`) when the jobs API lists its steps empty or cut short without the token step, so a refused run still gets its empty commit. A job that lists the token step as passed, and any job that is not a write-runner job, are still skipped.
- The red-main report counts a failed job that lists no failed step as a failing check of its own, matching the post-merge check.
- The demotion alert judges failing checks with red-main's rule (`failing-checks.mjs`) instead of its own shell copy. A failed job that lists no failed step now files, and, as a baseline entry, such a job excuses nothing.
