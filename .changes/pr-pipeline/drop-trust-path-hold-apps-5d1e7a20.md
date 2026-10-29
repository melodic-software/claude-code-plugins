---
bump: patch
---

### Changed

- The agent App trust-path hold is off (owner decision Q21, 2026-10-29: path holds stay off until
  open issues and pull requests reach zero). `merge.trust-path-hold-apps` names only
  `trust-path-hold-off[bot]`, a login no App holds, in place of `melodic-agent[bot]`, so neither
  ci-status's inline hold nor ci-workflows' `pr-require-checks-trust-paths` (through the
  regenerated `.github/trust-path-hold.json`) holds an agent App pull request for a person. The
  list keeps one entry because the shared workflow fails on an empty one. Listing
  `melodic-agent[bot]` again restores the hold.
- ci-status no longer holds a Dependabot, release-App or standards-sync-App pull request for
  changing a trust-gate path. `scripts/sync-hold-floor.py` writes ci-status's exempt-author
  `hold_patterns` only while `merge.diff-check.path-holds` is true and an empty list otherwise;
  this repository sets the new key false (owner decision Q21). Setting it true restores the
  hold. These authors still get no review lane.
