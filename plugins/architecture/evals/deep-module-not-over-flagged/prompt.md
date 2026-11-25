---
description: "An already-deep pricing module is not proposed for deepening; at most a Speculative card with its reason"
tags: [architecture, improve, row19, converted]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "Judges the pricing engine already deep (small interface, large tested implementation), says deepening would only move complexity, gives it no Strong or Worth exploring badge, and leaves the recorded in-process decision standing"
---

/architecture:improve deepening — review the pricing engine: a single Price(order) entry point backed by ~600 lines of rules, tax tables, and rounding policy, with a focused test suite that drives it only through Price(order). An architecture decision record already records keeping the rules in-process.
