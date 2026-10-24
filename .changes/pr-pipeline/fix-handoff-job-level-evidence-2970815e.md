---
bump: patch
---

### Fixed

- A handoff no longer depends on step data GitHub's jobs listing can return late or empty. Every handoff read (pr-unblock's five handoff jobs and `fix-ci-unreported`, and pr-refine's `fix-docs-handoff`) now runs one script, `.github/scripts/lib/handoff-evidence.sh`, which decides from job-level conclusions first: a skipped report job means no check was posted, and a new read-runner job, `broker-allowed`, succeeds only on broker-check's allow. Only a report that ran is read through its step, and that read is retried with backoff for about five minutes, then fails the job with one error line naming what stayed missing. Before, an empty step list read as "not allowed", so an empty or credit-stopped key ended the item stopped instead of starting the subscription leg, and as "not posted", which started a second leg after a call that had posted.
