---
description: "Fired at conversation start with no work yet, the sweep takes the cheap posture-digest path: it reports the core, situational and never tiers from metadata, states that nothing was audited, and dispatches no fork"
tags: [discipline, sweep-all, outcome]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Agent]
expected_outcome: "No Agent call; the reply reports the core, situational and never-batched tiers and says no audit ran (digest only)."
---

/discipline:sweep-all set our posture before we start
