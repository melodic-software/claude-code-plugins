---
bump: patch
---

### Fixed

- pr-feedback-dispatch.yml's rerun-ci-status records the ci-status re-run that a review run's
  attempt 2 causes when github-actions[bot] started that attempt and the lost-run reconciler's
  `reconcile-rerun-<run id>-2-<head>` record passes check-trusted-trigger's own reconciler check
  (`reconcilerRecordVouches`, run through `reconciler-record.mjs`), so pr-verify's trigger check
  accepts that ci-status attempt. Attempt 3, another re-runner, or a missing or refused record
  still records nothing.
