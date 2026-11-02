---
bump: minor
---

### Added

- The `upstream-apply-changelog` lane takes in one Claude Code release a run: a model job runs
  `/harness-ops:changelog apply --ci` with the API key and a read-only token, a scan job checks
  and credential-scans its sealed plan and branches, `push-branches` (`apply-changelog-branches`,
  mutate-branch) recreates each branch as signed lanes App commits, and `publish`
  (`publish-changelog-intake`, publish-artifact) opens one pull request per branch and files each
  handoff once. The token broker mints for it keyed on a new `release` request field.
