---
bump: patch
---

### Changed

- The pr-merge merge job now needs post-merge-dispatch, so it reads this run's kept post-merge report instead of racing its upload and running the same check again; on 2026-10-25, 20 of 43 scheduled runs read before the report was kept. `!cancelled()` keeps the job running on pull_request_target, where post-merge-dispatch is skipped, and when that job fails. The reuse rule (same main commit, under REUSE_MINUTES old) and the fallback to the job's own check are unchanged (`.github/workflows/pr-merge.yml`).
