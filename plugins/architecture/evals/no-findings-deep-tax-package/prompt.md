---
description: "A repo whose only module is already deep gets an explicit no-candidates verdict, not invented cards"
tags: [architecture, improve, row19, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "Scans the repo, finds tax already deep (compute_tax is the one entry point over rates, exemptions and rounding, tested only through it), and says plainly that there is no deepening candidate, with no Strong or Worth exploring card"
---

/architecture:improve deepening — scan this repository for deepening opportunities.
