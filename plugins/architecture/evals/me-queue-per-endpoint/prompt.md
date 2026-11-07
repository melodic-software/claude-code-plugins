---
description: "Setup.cs binds OrderHandler and BillingHandler on ReceiveEndpoint(\"orders\"), AuditHandler on ReceiveEndpoint(\"audit\"), then registers LateHandler with AddConsumer and publishes OrderPlaced: events.json puts the two orders consumers on queue orders, AuditHandler on audit, LateHandler and the publish edge on no queue, and raises a competing-consumer finding only for queue orders. Needs --scaffold and --allow-tools Bash."
tags: [architecture, map-events, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "docs/architecture/events.json has consume edges at src/Orders/Setup.cs lines 24 and 29 on queue orders, line 34 on queue audit and line 39 on queue -, a publish edge at line 21 with queue -, no publish edge with a queue, and one competing finding for Orders.Contracts.OrderPlaced reading 2 consumers on queue orders and none for another queue."
---

/architecture:map-events
