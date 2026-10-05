---
description: "Control. The prompt states the bar (production, relied on by paying customers), so round 1 must not ask it again and its depth should match production. Row 38 of the Pocock sync."
tags: [interview, quality-bar, row38]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 1 asks scoping questions without asking the quality bar again, and includes at least one production concern (failure handling, data correctness, security, monitoring, or rollback)"
---

/planning:interview We need a nightly service that exports each customer's invoices to their accounting system. This goes to production and our paying customers will rely on it for their month-end close.
