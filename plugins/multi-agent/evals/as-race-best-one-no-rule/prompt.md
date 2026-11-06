---
description: "Legacy assess 4 wording: four agents get the same brief and the user keeps 'the best one', which names no criterion. assess SKILL.md lines 27-29 and 76-79: a race states its selection rule before any agent is spawned; with none stated the shape is race (no selection rule stated) and the reason says the race must not start until one is. as-race-no-selection-rule says 'keep one'; this case adds the word that looks like a rule. Graders copied from that case."
tags: [multi-agent, assess, outcome, race, no-network]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash, Agent]
expected_outcome: "verdict: subagent; shape: race (no selection rule stated), not a best-of rule read from 'the best one'; the reason line says the race must not start until a selection rule is stated. No agent is spawned."
---

/multi-agent:assess Four subagents each write a fix for the same flaky test in tests/cart/checkout.spec.ts from the same brief, and then I keep the best one.
