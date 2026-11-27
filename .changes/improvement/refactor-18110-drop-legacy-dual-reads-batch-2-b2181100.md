---
bump: minor
---

### Removed

- **Dropped legacy `.claude/` and `~/.claude/` dual-reads.** `/improvement:find` and `/improvement:setup` now read only the canonical config-cascade layers (`userConfig` options, `<home>/improvement.yaml`, and `<home>/improvement.local.yaml`) and no longer read or migrate `~/.claude/improvement.md`, `.claude/improvement.md`, or `.claude/improvement.local.md`.

### Changed

- **Demoted `improvement-r001` and `improvement-r002` to `report-only`.** `retirements.yaml` keeps both records as history reported at INFO without failing checks or offering cleanup.
