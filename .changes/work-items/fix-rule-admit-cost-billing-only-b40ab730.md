---
bump: patch
---

### Fixed

- `rule-admit.sh` no longer refuses Claude work for naming its cost: a spend word (cost, spend, spending, pricing, paid, quota) is exempt only when the issue names Claude or Anthropic and names no other provider, vendor, service, plan or metered resource (GitHub, Azure, AWS, Google, OpenAI, Vercel, Stripe, storage, hosting and the like). A bare "model" or "eval" does not exempt. Charge terms (billing, a spending limit, a subscription, a seat, Codespaces, a paid plan, a top-up, auto-renew, auto-reload, extra usage, retention, a larger or hosted runner, macOS minutes) still refuse every issue (owner decision 2026-10-24, #9904).
