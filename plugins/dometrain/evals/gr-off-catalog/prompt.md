---
description: "Regression guard, likely null in both arms. SKILL.md When to consult Dometrain: 'Skip it for topics clearly outside the catalog.' A spreadsheet formula question is outside every catalog area the skill lists, so the run does not invoke dometrain:grounding, does not send the user to /dometrain:setup, and answers with a SUMIFS or SUMIF formula. A model without the plugin passes too, so this case scores nothing; it guards against a description rewrite that makes grounding fire on everything. Paired hard case: gr-deep-link-demand. Read-only tools only; no grant needed."
tags: [dometrain, grounding, outcome, routing, regression-guard]
max_turns: 6
timeout_seconds: 240
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run makes no Skill call to dometrain:grounding. The reply does not mention dometrain:setup and gives a SUMIFS( or SUMIF( formula."
---

In a spreadsheet, column A holds an invoice status ("paid" or "open") and column B the amount. What formula sums column B for only the paid rows?
