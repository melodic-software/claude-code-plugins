---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['improve', 'narration']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Reads the ''Where boundary rules live'' list from the enforcement-ladder copy, records the ARCHITECTURE.md rule with its source line, reads the existing dependency graph, and reports the Reports-to-Ledger edge as a crossing citing both the rule''s source line and the edge''s manifest evidence. After the user confirms, it writes one review-findings file under .work/improve/feature-billing-split/ (after checking that the memory root carries a .gitignore with *), with the rule as a row under an architecture dimension heading, names that file in the report, and offers /corrections:codify findings on it without running it.'
---

/architecture:improve boundaries. We are on branch feature/billing-split. ARCHITECTURE.md line 14 says "Billing.Reports must not reference Billing.Ledger directly." The architecture topic doc declares architecture_dir: docs/architecture, and docs/architecture/dependency-graph.json is current and has a resolved project edge from src/Billing.Reports/Billing.Reports.csproj to src/Billing.Ledger/Billing.Ledger.csproj. When you show me the crossing I will confirm the rule for enforcement.
