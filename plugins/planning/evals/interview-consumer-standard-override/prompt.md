---
description: "The repository's docs/standards/integrations.md puts every external service behind an interface from its first implementation; the user says no second provider is coming: the interview reads that standard, applies it over the bundled wait-for-repetition default, and records the override line naming the standards file"
tags: [interview, standards, override, engineering-defaults]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The interview reads docs/standards/integrations.md, and .work/address-validation/PLAN.md carries 'Overrides bundled default <principle> per docs/standards/integrations.md', with the address-validation interface required from the first implementation despite the speculative second variant"
---

/planning:interview lock

Lock the Brief. Use the topic slug `address-validation`.

Goal: checkout catches an undeliverable delivery address before payment, using the Loqate API. This goes to production. Loqate is the only provider and nothing says another is coming.

Acceptance: an address Loqate marks undeliverable keeps the Pay button disabled and shows a message.
