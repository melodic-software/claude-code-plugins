---
bump: patch
---

### Fixed

- pr-merge.yml's merge job now files the demotion record for a failed lane merge. When its
  read-only post-merge check exits 1, it runs the check again with `--remediate` under the lanes App
  token, which files (or comments on, reopening) the record and dequeues the lane's merge-queue
  entries, so a human closing that record re-arms the lane. Before, a red full run this workflow
  dispatched with `GITHUB_TOKEN` raised no `workflow_run` event, post-merge-demotion-alert.yml never
  saw it, and the gate refused every candidate with no record a human could close.
- That step judges the remediation by its report, not its exit code: a missing report or a failed
  record filing or dequeue raises an error annotation, and only the expected refused re-run and
  dispatch attempts warn.
- post-merge-demotion-alert.yml also reads records the lanes App filed and treats a record of either
  filer that names the same failing run as this run's record, so one red run no longer gets two. Its
  record says the lane stays at rung off while any demotion record is open: fix main first, then close
  every open record.
