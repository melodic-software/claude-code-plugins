---
bump: minor
---

### Changed

- `babysit_risk.HIGH_FLOOR` holds only a narrow floor (owner decision Q-FLOOR (B)): `.github/actions/resolve-config/**`, `.github/actions/request-lane-token/**`, `.github/actions/check-trusted-trigger/**`, `.github/actions/check-kill-switch/**`, `.github/actions/log-api-budget/rate-guard.mjs`, `**/CODEOWNERS` and `**/.gitmodules`, and it scores HIGH whatever `high-path-floor` says, which now turns off only the manifest review. The trusted-actor directory left the floor: the trust gate holds a widening of the list. No other path scores HIGH for being trusted alone; a configured denied path, the trust gate and the cost hold still do.
- `plugins/multi-agent/reference/defaults.yaml` is no longer a `COST_PATHS` entry; the infrastructure-as-code entries stay.
