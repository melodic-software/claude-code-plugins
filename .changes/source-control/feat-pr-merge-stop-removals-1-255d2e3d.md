---
bump: minor
---

### Changed

- `babysit_risk.HIGH_FLOOR` is empty (owner direction 2026-10-24): no path scores HIGH for being trusted alone; a configured denied path, the trust gate and the cost hold still do.
- `plugins/multi-agent/reference/defaults.yaml` is no longer a `COST_PATHS` entry; the infrastructure-as-code entries stay.
