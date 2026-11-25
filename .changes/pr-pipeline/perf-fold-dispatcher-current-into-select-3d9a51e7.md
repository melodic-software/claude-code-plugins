---
bump: patch
---

### Changed

- pr-unblock's `Check Dispatcher Current` job now runs only for review-dependency. The other activities' first jobs (four select jobs and `fix-ci-context`) compare the dispatcher's copy of its file with the tip's as a step before their kill-switch step, as pr-refine's `select-passes` already does. A stale dispatcher stops the job before it reads the PR, so its outputs stay empty, no later job starts and the run ends green, as before. Each such run starts one job fewer and skips one queue wait, measured at 171 s queued for 5 s of work on run 45662117298. Each of those jobs already holds `actions: read` and `contents: read`, the old job's whole grant; `review-dependency-select` holds no `actions: read`, so it keeps the separate job rather than widen.
