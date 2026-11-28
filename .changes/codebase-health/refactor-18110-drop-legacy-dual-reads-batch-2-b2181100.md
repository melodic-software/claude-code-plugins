---
bump: major
---

### Removed

- **Dropped legacy `.claude/` and `~/.claude/` dual-reads.** `/codebase-health:audit` and `/codebase-health:setup` now read only the canonical config-cascade layers (`dimensions_file` `userConfig` option, `<home>/codebase-health.md`, and `<home>/codebase-health.local.md`) and no longer read or migrate `~/.claude/codebase-health.md`, `.claude/codebase-health.md`, or `.claude/codebase-health.local.md`.

### Changed

- **Demoted `codebase-health-r001` and `codebase-health-r002` to `report-only`.** `retirements.yaml` keeps both records as history reported at INFO without failing checks or offering cleanup.
