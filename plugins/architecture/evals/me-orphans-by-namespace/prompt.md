---
description: "Billing publishes Billing.Contracts.OrderPlaced and Shipping consumes Shipping.Contracts.OrderPlaced: the event map keeps them as two messages, reports an orphan publisher and an orphan consumer, and keeps the unresolved Publish(audit) as a finding"
tags: [architecture, map-events, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "events.json lists Billing.Contracts.OrderPlaced and Shipping.Contracts.OrderPlaced as two messages, has an orphan-publisher finding for the Billing type and an orphan-consumer finding for the Shipping type, and an unresolved finding citing src/Billing/CheckoutService.cs:16; the final reply names both namespace-qualified types."
---

/architecture:map-events --out docs/architecture
