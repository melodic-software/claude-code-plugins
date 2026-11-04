---
bump: patch
---

### Fixed

- work-resolve-issue holds through a read outage instead of failing. `report-outcome.mjs
  --find-prior` ends green with a notice and `proceed=false` on a failed read, so no model runs and
  a later run reads again. A run whose `merge: human` labeler cannot be read opens no PR and posts
  nothing, and the next run opens it from the unreported branch. A stop past `limits.stop-retries`
  no longer fails the issue when it and every counted retry were faults in the lane's machinery
  (`fault: true` in `stop-routes.json`), unless the run left a branch of its own.
