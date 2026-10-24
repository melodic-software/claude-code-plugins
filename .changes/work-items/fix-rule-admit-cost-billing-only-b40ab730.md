---
bump: patch
---

### Fixed

- `rule-admit.sh` refuses an issue as a cost hit only when its title or body names a metered or renewing charge: billing, billed, a spending limit, a subscription, a SKU, retention, a larger, hosted or self-hosted runner, or macOS minutes. The bare words cost, spend, spending, pricing, paid and quota no longer refuse, so an issue about a model or eval run is admitted by rule (owner decision 2026-10-24).
