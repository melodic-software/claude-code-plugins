---
description: "improve boundaries lens over a scaffolded repository: the ARCHITECTURE.md:14 rule, a convention home whose topic doc sets architecture_dir docs/architecture, and a current dependency-graph.json with the Billing.Reports to Billing.Ledger edge. The lens takes its sources from the enforcement-ladder list, reports the edge as a crossing citing the rule's line and the manifest evidence, writes nothing under .work/reviews/, offers /corrections:codify findings without running it, and edits no source file. Source: the improve skill's evals.json case boundaries-recorded-rule-crossing-handed-on, given a scaffold. Needs --scaffold --allow-tools Bash Write and a sandbox backend."
tags: [architecture, improve, boundaries, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Reads the 'Where boundary rules live' list from the enforcement-ladder copy, records the ARCHITECTURE.md:14 rule, reads the existing dependency graph, reports the src/Billing.Reports to src/Billing.Ledger edge as a crossing citing the rule's line and the manifest declaration, writes any findings file under .work/improve/feature-billing-split/ and none under .work/reviews/, offers /corrections:codify findings without invoking it, and edits no source file."
---

/architecture:improve boundaries. We are on branch feature/billing-split. ARCHITECTURE.md line 14 says "Billing.Reports must not reference Billing.Ledger directly." The architecture topic doc declares architecture_dir: docs/architecture, and docs/architecture/dependency-graph.json is current and has a resolved project edge from src/Billing.Reports/Billing.Reports.csproj to src/Billing.Ledger/Billing.Ledger.csproj. When you show me the crossing I will confirm the rule for enforcement.
