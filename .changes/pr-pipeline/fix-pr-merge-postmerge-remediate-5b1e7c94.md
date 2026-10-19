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
