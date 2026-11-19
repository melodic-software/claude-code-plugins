---
bump: patch
---

### Changed

- `maintenance-reconcile-lost-runs` runs hourly at minute 4 instead of at minutes 4 and 34, and its dispatch gap (`MIN_GAP_MINUTES`) is 60. A pass costs about 90 GITHUB_TOKEN calls and the pool ran out in busy hours, so this halves the reconciler's share. fix-ci waits for the reconciler's one re-run of an infra-only failure for `RERUN_DUE_MINUTES`, now its backoff plus two hourly ticks (135 minutes). `pr-unblock-dispatch.yml` keeps its 9 and 39 ticks; the 9 tick still follows the reconciler's.
