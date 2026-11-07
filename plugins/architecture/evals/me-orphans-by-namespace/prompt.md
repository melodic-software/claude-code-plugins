---
description: "Billing publishes Billing.Contracts.OrderPlaced and sends Billing.Contracts.ChargeCard, Shipping consumes Shipping.Contracts.OrderPlaced, and the convention home declares landscape_dialect structurizr: the event map keeps the two OrderPlaced types as two messages, reports orphan publisher and orphan consumer, keeps the unresolved Publish(audit) and Send(new RefundRequested) as findings that satisfy no consumer, writes events.md as a mermaid flowchart and no events.dsl, passes no --dialect to render-events.sh, writes handoff lines keyed by file and line, never claims map-flow reads events.md, and offers the interactive view without building it. Needs --scaffold and --allow-tools Bash."
tags: [architecture, map-events, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "events.json lists Billing.Contracts.OrderPlaced and Shipping.Contracts.OrderPlaced as two messages, has an orphan-publisher finding for the Billing type and an orphan-consumer finding for the Shipping type, and unresolved findings citing src/Billing/CheckoutService.cs:16 (publish) and :17 (send). events.md is a mermaid flowchart with handoff lines for the OrderPlaced publish at line 15 and the ChargeCard send at line 18; no events.dsl is created and no render-events.sh call passes --dialect. The final reply names both namespace-qualified types, does not claim map-flow reads events.md, and offers the interactive view; no build-view.mjs call runs."
---

/architecture:map-events
