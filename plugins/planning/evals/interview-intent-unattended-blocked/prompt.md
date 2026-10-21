---
description: "Unattended lock where only a triage bot's issue note says more providers are coming: the repeat-or-vary part stays unstated, so the Brief is still written, the intent row is blocked and deferred with arbiter USER-RESERVED, and the run names that blocker"
tags: [interview, intent, unattended, engineering-defaults]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: ".work/address-validation/PLAN.md is written; its Captured assumptions carry Variation intent: second variant = blocked, its Deferred questions carry a Q<N> entry on whether a second provider is coming tagged USER-RESERVED, no Variation intent line settles known, category or speculative, and the reply names the blocker"
---

/planning:interview lock

This run is unattended: nobody will answer questions, so record anything only I can decide as blocked and keep going. Use the topic slug `address-validation`.

Lock the Brief for `docs/issues/412.md`. Goal: checkout catches an undeliverable delivery address before payment. This goes to production. Acceptance: an address Loqate marks undeliverable keeps the Pay button disabled and shows a message; if Loqate takes longer than 2 seconds, checkout proceeds and logs a warning.
