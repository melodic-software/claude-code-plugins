---
description: "OrderService publishes OrderPlaced by its short name through using Contracts, its consumer is registered with AddConsumer, Publisher in namespace Shop publishes Contracts.InvoiceIssued (declared as Shop.Contracts.InvoiceIssued) and the undeclared Vendor.Sdk.Ping, and InventoryReport is never published, sent or consumed: events.json resolves the short name to Contracts.OrderPlaced and the dotted name through the enclosing namespace to Shop.Contracts.InvoiceIssued, keeps Vendor.Sdk.Ping as an unresolved publish and not an orphan publisher or message, and lists no consumer, service or unused class as a message and no orphan. Needs --scaffold and --allow-tools Bash."
tags: [architecture, map-events, outcome, scaffold, no-network]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "docs/architecture/events.json holds a static publish edge from src/Orders/OrderService.cs to Contracts.OrderPlaced and one from src/Shop/Publisher.cs to Shop.Contracts.InvoiceIssued, an unresolved finding for Vendor.Sdk.Ping citing src/Shop/Publisher.cs:11, no message or orphan for Vendor, no orphan finding of any kind, and no message id for OrderPlacedConsumer, InvoiceIssuedConsumer, InventoryReport, Startup, OrderService or Publisher."
---

/architecture:map-events
