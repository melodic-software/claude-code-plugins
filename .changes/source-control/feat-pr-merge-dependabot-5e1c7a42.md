---
bump: minor
---

### Added

- The unattended merge gate's pr-merge lane (`--authority pr-merge`) merges Dependabot pull requests as their own class: tier `auto` (verified Dependabot commits, every update semver-patch or semver-minor) merges on a green `ci-status` with no closing issue, denied-path rule or diff score; tier `review` (a major, an unknown update type, any other commit, a failed `ci-status`) is refused. `merge.dependabot.mode` (`off`, `report`, `enforce`) switches it apart from `merge.report-only`. The local babysit paths still hold every dependency-manager PR.
