---
description: "Cost claims link the costs and pricing docs and state no prices or per-task figures; `docs/upstream/` records may list vendor figures labeled vendor-reported"
paths:
  - "plugins/*/skills/**"
  - "plugins/*/agents/**"
  - "plugins/*/reference/**"
  - "docs/**/*.md"
  - "prompts/**"
---

# Cost claims point at the docs

Prices and what a task costs change with each model and plan, so text here links the page that
owns them instead of restating them:

- What drives usage and how to read it, `/usage` included:
  [Manage costs: Track your costs](https://code.claude.com/docs/en/costs#track-your-costs).
- Rates: [Pricing](https://platform.claude.com/docs/en/about-claude/pricing).

Never write a price, a cache or batch rate, a per-task or per-session cost, or a percentage saving
into a skill, agent, reference, doc or prompt. A mechanism, such as each turn resending the
conversation, is fine; the number is the docs' to state.

On a subscription the `/usage` session cost is a list-price estimate of the work, not a bill, as
the costs page says. Do not present it as spend.

One exception: a record under `docs/upstream/` may list a post's figures, each labeled
vendor-reported, because recording what the post said is its job. Guidance elsewhere links the
record and copies none of its figures.

Basis: the two pages above, checked 2026-10-01. Recheck when either page moves the section linked
here.
