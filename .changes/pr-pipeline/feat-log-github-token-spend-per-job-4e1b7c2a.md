---
bump: patch
---

### Changed

- API budget logging reads the rate limit from each job's own responses. It no longer reads `GET /rate_limit`, which reports a different bucket from the one the job spends. `.github/actions/log-api-budget` holds three parts:
  - `api-budget.bash`: a `gh` wrapper and the notice
  - `api-budget.mjs`: the fetch side
  - an end-of-job emitter
- Each named token gets one notice for its last reading and one for each refused (403/429) reading: `token=<name> workflow=<path> job=<id> run=<id> attempt=<n> limit= remaining= used= reset=<epoch> resource= cost=<N or na>`. `cost` is how much `used` rose since the first reading with the same reset.
- Where the notices come from:
  - `ci-status` wraps its own `gh api` reads and writes its notice before the aggregate step.
  - pr-merge's merge job reads through the babysit gh seam.
  - The pr-feedback-dispatch and pr-unblock-dispatch jobs read through `request-budget.mjs`.
  - Those three jobs write their notices from their existing end steps.
- The start-of-job `/rate_limit` steps are gone, including those in work-unblock, intake-triage and pr-run-activity-write.
- The lanes App token is now named `lanes-app` (it was `lane`). The monitor-signals ceiling reads both names and both notice shapes.
