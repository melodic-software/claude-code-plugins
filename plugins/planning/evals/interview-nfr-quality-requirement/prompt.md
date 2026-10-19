---
description: "Production lock whose request states a latency target, a degraded-provider behavior and a logging restriction: the Brief records each under Constraints as a Quality requirement line, and records the Intent and Quality bar lines under Captured assumptions"
tags: [interview, quality-requirements, nfr, engineering-defaults]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: ".work/address-validation/PLAN.md has, under ### Constraints, a '- Quality requirement:' line carrying the 300 ms p95 target and another for proceeding when Loqate is down or slower than 2 seconds; its Captured assumptions carry 'Quality bar: production' and 'Intent: second variant = speculative'"
---

/planning:interview lock

Lock the Brief. Use the topic slug `address-validation`.

Goal: checkout catches an undeliverable delivery address before payment, using the Loqate API. This goes to production. Only checkout needs it, and nothing says another provider is coming, so keep it specific to Loqate.

Acceptance: an address Loqate marks undeliverable keeps the Pay button disabled and shows a message. Undeliverable means Loqate returns an unverified result; partial and ambiguous matches let checkout proceed. The Pay button lives in our separate web client, which renders a `canPay` flag and a message that checkout in this repo returns.

Quality: the lookup adds at most 300 ms to checkout at p95. If Loqate is down or takes longer than 2 seconds, checkout proceeds and logs a warning. Never log the full address.
