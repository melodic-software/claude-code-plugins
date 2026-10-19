---
bump: patch
---

### Fixed

- pr-merge.yml's merge job now files the demotion record when its read-only post-merge check
  exits 1 (a failed lane merge: a canary or read-back failure, a missed dispatch deadline, or a red
  full run whose attempt 2 the agent identity did not start). It runs the check again with
  `--remediate` under the lanes App token, which files (or comments on, reopening) the record and
  dequeues the lane's merge-queue entries, so a human closing that record re-arms the lane. A full
  run this workflow dispatched with `GITHUB_TOKEN` raises no `workflow_run` event, so
  post-merge-demotion-alert.yml never files for it; when a human re-runs such a red run (run
  39200031682, red attempt 1, human attempt 2), the check reads it red and this step files the record.
  A red dispatched run that nobody re-runs still waits for its one re-run (exit 5) and files nothing;
  the lanes App cannot start that re-run.
- That step judges the remediation by its report, not its exit code: a missing report or a failed
  record filing or dequeue raises an error annotation, and only the expected refused re-run and
  dispatch attempts warn.
- post-merge-demotion-alert.yml also reads records the lanes App filed and treats a record of either
  filer that names the same failing run as this run's record, so one red run no longer gets two. Its
  record says the lane stays at rung off while any demotion record is open: fix main first, then close
  every open record.
