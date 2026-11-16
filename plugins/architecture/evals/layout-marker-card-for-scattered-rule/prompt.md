---
description: "improve-layout Phase 2 marker card: the scaffolded ARCHITECTURE.md:22 rule governs three files that share no folder and no file-name part, so the rule gets a marker card proposing a shared file-name part, routed to /architecture:improve conventions; no file is renamed. Source: the improve skill's evals.json case layout-marker-card-for-scattered-rule, given a scaffold. Needs --scaffold --allow-tools Bash Write and a sandbox backend."
tags: [architecture, improve-layout, co-change, scaffold]
runs: 6
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Cites ARCHITECTURE.md:22 as the rule's source, states that src/billing/invoice.ts, src/reports/ledger-view.ts and lib/tax.ts share no folder and no file-name part, presents a marker card proposing a shared file-name part for them, routes it to /architecture:improve conventions, and renames no file."
---

/architecture:improve-layout. ARCHITECTURE.md line 22 records: "The files src/billing/invoice.ts, src/reports/ledger-view.ts and lib/tax.ts hold the tax rules and must change only through a reviewed tax change." No other layout style is recorded. I am here to answer questions.
