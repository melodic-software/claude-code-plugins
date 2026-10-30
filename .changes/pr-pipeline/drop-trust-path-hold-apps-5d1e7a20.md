---
bump: patch
---

### Changed

- The agent App trust-path hold is off (owner decision Q21, 2026-10-29: path holds stay off until
  open issues and pull requests reach zero). `merge.trust-path-hold-apps` names only
  `trust-path-hold-off[bot]`, a login no App holds, in place of `melodic-agent[bot]`, so neither
  ci-status's inline hold nor ci-workflows' `pr-require-checks-trust-paths` (through the regenerated
  `.github/trust-path-hold.json`) holds an agent App pull request for a person, except that both
  still fail closed on a read they cannot finish: a pull request past 250 commits or 3000 files, or
  a branch history past 2000 entries. The list keeps one entry because the shared workflow fails on
  an empty one. Restoring both holds takes three steps: list `melodic-agent[bot]` again, set
  `merge.diff-check.path-holds` true and run `scripts/sync-hold-floor.py`. Listing the App alone
  restores only ci-workflows' hold, since ci-status's inline hold runs only while `path-holds` is
  true.
- ci-status no longer holds a release-App or standards-sync-App pull request for changing a
  trust-gate path, and still holds a Dependabot one, whose action-pin bumps bring in third-party
  code (owner decisions Q21 and Q24). While `merge.diff-check.path-holds` is false, as this
  repository sets the new key, `scripts/sync-hold-floor.py` writes a guard after ci-status's
  exempt-author `hold_patterns` that empties the list for every author but Dependabot. Setting
  it true holds all three again. These authors still get no review lane.
