---
bump: minor
---

### Added

- The unattended merge gate's pr-merge lane (`--authority pr-merge`) merges Dependabot pull requests as their own class, on a green `ci-status` with verified Dependabot commits and no closing issue, denied-path rule or diff score. Tier `auto` (every update non-major, counting a 0.x minor change as major; Actions publishers `actions`, `github` or `anthropics` only; `ci-status` not red) merges directly; tier `review` merges only on the lanes App's `verdict=merge` review-dependency round marker at the current head, and may then carry the App's `[dependabot skip]` fix commits. `merge.dependabot.mode` (`off`, `report`, `enforce`) switches it apart from `merge.report-only`. The local babysit paths still hold every dependency-manager PR.
