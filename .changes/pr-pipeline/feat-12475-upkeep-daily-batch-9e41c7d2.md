---
bump: minor
---

### Added

- The `maintenance-code-tidying-upkeep` lane opens code-tidying pull requests as a daily batch: a
  gate picks the areas, a model job runs `/code-tidying:tidy` on the automations subscription token
  with a read-only token, a scan job checks and credential-scans its sealed plan and branches,
  `push-branches` (`apply-upkeep-branches`, mutate-branch) recreates each branch as a lanes App
  commit, and `publish` (`publish-upkeep-prs`, publish-artifact) opens the pull requests within
  `upkeep_max_open`. Its `scan` job is the scan-carrier key's third holder (owner decision,
  2026-11-03).
