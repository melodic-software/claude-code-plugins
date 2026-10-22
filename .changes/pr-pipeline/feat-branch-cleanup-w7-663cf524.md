---
bump: minor
---

### Added

- A `branch-cleanup` leaf (`max-deletes-per-run`, default 25) and the daily
  maintenance-delete-stale-branches.yml that applies it: a branch lives as long as its issue is
  open, and one whose pull request closed or merged and whose linked issue closed is deleted, at
  most `max-deletes-per-run` a run with the calls those deletes need reserved first, after a re-read of its tip and open pull requests and a
  ledger line in the step summary and an artifact. A lane run's stop marker does not keep a
  branch once its issue closed. A branch with an open issue or pull request, and a protected or
  ruleset branch, are never deleted; a branch that never had a pull request, or whose tip moved
  after its pull request closed with commits ahead, is listed for a person. A manual run is a
  dry-run by default.
