---
bump: patch
---

### Fixed

- A head whose CI job ran past its `timeout-minutes` is no longer left red with no lane acting on it. GitHub ends such a job `cancelled`, and only its check run's annotation ("The job has exceeded the maximum execution time") says why; fix-ci-context and the fix-ci dispatcher now read that annotation and count the job as failing, so fix-ci works on the slow or hanging test, with the time-limit note in its context. A check cancelled with no such note stays skipped (`.github/scripts/pr-unblock/fix-ci-context.mjs`, `.github/scripts/pr-unblock/fix-ci-dispatch.mjs`).
- The fix-ci dispatcher waits for the lost-run reconciler's one re-run of a cancelled, timed-out or start-failed first attempt, as it already does for an infra-only failure, so the two do not act on the same head at once (`.github/scripts/maintenance-reconcile-lost-runs/infra-failure.mjs`).
- The lost-run reconciler names each CI run lost again after its one re-run in its run summary, with who takes it (`.github/scripts/maintenance-reconcile-lost-runs/reconcile.mjs`).
