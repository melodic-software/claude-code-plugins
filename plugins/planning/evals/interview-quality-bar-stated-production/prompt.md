---
description: "Control. The prompt states the bar (production, relied on by paying customers), so the interview must not ask it again and its depth should match production. The prompt starts past the intake round, so production concerns, which are decision questions, come in round 2. Row 38 of the Pocock sync."
tags: [interview, quality-bar, row38, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Round 2 asks scoping questions without asking the quality bar again, and includes at least one production concern (failure handling, data correctness, security, monitoring, or rollback) as a question"
---

/planning:interview We need a nightly service that exports each customer's invoices to their accounting system. This goes to production and our paying customers will rely on it for their month-end close.

Round 1, the intake round, is answered: Q1, the problem is that customers' finance staff re-key our invoices into their accounting systems by hand every month-end, and typing errors delay their close; Q2, it is for those finance staff, and for our support team, who field questions when an invoice is missing.

Ask me round 2 now, then stop for my answers.
