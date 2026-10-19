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

This run is unattended: nobody will answer questions, so record anything only I can decide as blocked and keep going.

Lock the Brief. Use the topic slug `address-validation`.

Goal: checkout catches an undeliverable delivery address before payment, using the Loqate API. This goes to production. Loqate is the only provider and nothing says another is coming.

Acceptance: an address Loqate marks undeliverable keeps the Pay button disabled and shows a message. Undeliverable means Loqate returns an unverified result; partial and ambiguous matches let checkout proceed. The Pay button lives in our separate web client, which renders a `canPay` flag and a message that checkout in this repo returns. If Loqate cannot answer (an error, an outage or a timeout), checkout fails open: Pay stays enabled.
