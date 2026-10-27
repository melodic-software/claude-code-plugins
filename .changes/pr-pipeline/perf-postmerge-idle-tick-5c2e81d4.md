---
bump: patch
---

### Changed

- pr-merge's post-merge-dispatch job reads the post-merge report that the last scheduled or hand-started run kept. It reads only a run on main and finds it the way it finds the lane records (`.github/scripts/pr-merge/last-report.mjs`). On an idle tick it reuses that report and does not run "Check earlier lane merges". It keeps the report's `computedAt`, exit code and code commit, so a chain of reuses ends `SHARED_MAX_AGE` after the check that made the report. Any refusal or failed read runs the check as before. `last-report.mjs` is gate code on the risk floor.
