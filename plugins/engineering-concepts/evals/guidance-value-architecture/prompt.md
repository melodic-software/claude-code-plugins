---
description: "Value test, not for merge: does the team's design guidance change an architecture proposal? Compare run, merge base (no guidance skill) against head (design-guidance skill). Graders check the core-styles, vertical-slice and shared-database-context positions in the reply."
tags: [engineering-concepts, guidance-value]
max_turns: 8
timeout_seconds: 300
expected_outcome: "The proposal weighs event-driven, message bus and layered or clean styles, uses vertical slices, and shares the database context across slices."
---

We're starting a new order-management backend for a mid-size retailer: orders, payments, inventory and shipping notifications. Propose the architecture: the style or styles, how the code is organized into modules, and how those modules use the database. Before you answer, use any design guidance our installed skills offer. Keep it under 600 words.
