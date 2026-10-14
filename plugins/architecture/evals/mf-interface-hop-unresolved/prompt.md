---
description: "Tracing POST /orders: the call through IOrderService stays an unresolved interface hop that is never bound to OrderService, and the Publish<OrderPlaced> is an asynchronous hand-off to map-events"
tags: [architecture, map-flow, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "flow.json records the Place call at src/Controllers/OrdersController.cs as unresolved with mechanism interface, holds no hop into OrderService.cs or OrderRepository.cs, and records Publish<OrderPlaced> as an asynchronous hand-off; flow.md draws that hand-off naming /architecture:map-events; the final reply reports one interface or DI hop (di=1)."
---

/architecture:map-flow "POST /orders" --out docs/architecture
