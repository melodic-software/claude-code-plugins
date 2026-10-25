---
bump: patch
---

### Fixed

- `rule-admit.sh` no longer refuses an issue for naming Claude spend: a spend word (cost, spend, spending, pricing, quota) is exempt only inside a phrase such as "Claude eval cost" or "Claude API key spend", and only when the issue names none of a closed list of other charge sources (GitHub, Azure, AWS, Google, OpenAI, Vercel, Stripe, storage, hosting, and the generic provider, vendor, service and plan). Any other spend-word occurrence, including "paid", refuses, so an unlisted provider's charge still waits. Charge terms (billing, a spending limit, a subscription, a seat, Codespaces, a paid plan, a top-up, auto-renew, auto-reload, extra usage, retention, a larger or hosted runner, macOS minutes) refuse every issue (owner decision 2026-10-24, #9904).
