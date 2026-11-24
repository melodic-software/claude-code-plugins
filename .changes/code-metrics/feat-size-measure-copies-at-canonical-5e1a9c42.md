---
bump: minor
---

### Added

- `/code-metrics:audit size --check` reads `scope.registries` cluster lines
  (`<canonical> -> <member>...`): a file a cluster line names as a member is a copy measured at
  its canonical, listed with the canonical's path and never failing on its own count. The
  canonical keeps the rule.
