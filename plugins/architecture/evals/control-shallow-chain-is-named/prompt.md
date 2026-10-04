---
description: "Control: a real shallow pass-through chain is named as a candidate, so an always-empty verdict cannot pass the row 19 cases"
tags: [architecture, improve, row19, scaffold, control]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "Names the OrderHandler -> OrderValidator -> OrderRepo chain as a deepening candidate (shallow pass-through hops with the pricing rules spread across them) and does not report that the repository has no candidates"
---

/architecture:improve deepening — scan this repository for deepening opportunities.
