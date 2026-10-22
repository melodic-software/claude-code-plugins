---
bump: minor
---

### Added

- A `branch-cleanup` leaf (`min-age-days`, default 14; `max-deletes-per-run`, default 25) and
  the daily maintenance-delete-stale-branches.yml that applies it: a branch whose pull request
  closed or merged and whose linked issue closed at least `min-age-days` ago is deleted, oldest
  first and at most `max-deletes-per-run` a run, after a re-read of its tip and open pull
  requests and a ledger line in the step summary and an artifact. A branch with an open issue
  or pull request, a protected or ruleset branch, and a stopped lane run's branch are never
  deleted; a branch that never had a pull request, or whose tip moved after its pull request
  closed with commits ahead, is listed for a person. A manual run is a dry-run by default.
