---
bump: patch
---

### Fixed

- `rule-admit.sh` no longer refuses Claude, model or eval work for naming its cost: a spend word (cost, spend, spending, pricing, paid, quota) is exempt when the issue is model or eval work and names no other provider or metered service such as GitHub, Azure, Actions, Copilot, LFS, storage or hosting. Charge terms (billing, a spending limit, a subscription, a seat, Codespaces, a paid plan, a top-up, auto-renew, auto-reload, extra usage, retention, a larger or hosted runner, macOS minutes) still refuse every issue (owner decision 2026-10-24).
