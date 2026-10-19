---
description: "Production integration design whose Brief already records a 300 ms p95 performance requirement, a degraded-provider reliability requirement and a logging restriction: the first round designs to them as settled inputs and asks none of them again"
tags: [design, quality-requirements, nfr, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The first design round cites the Brief's 300 ms p95 lookup budget (and the proceed-on-outage rule) as settled inputs to its recommendations and asks no question that re-opens the latency target, the outage behavior or the logging restriction. No .js file is written or edited"
---

/planning:design integration

Topic slug `address-validation`; the Brief is in `.work/address-validation/PLAN.md`. Run the first discussion round with your recommendations, then stop for my answers. Don't write any code.
