---
bump: patch
---

### Changed

- pr-unblock no longer starts a separate `Check Dispatcher Current` job. Each activity's first job (the five select jobs and `fix-ci-context`) compares the dispatcher's copy of its file with the tip's as a step before its kill-switch step, as pr-refine's `select-passes` already does. A stale dispatcher stops the job before it reads the PR, so its outputs stay empty, no later job starts and the run ends green, as before. Each pr-unblock run starts one job fewer and skips one queue wait, measured at 171 s queued for 5 s of work on run 45662117298. The select jobs keep their own permissions (`actions: read` and `contents: read` at least, the old job's whole grant), and resolve their standards commit themselves.
