---
description: "System-scope design on a production Brief with two quality requirements and no stated peak load: design-threads.md records a Risks thread whose rows use /planning:plan's risk-table columns (Risk | Likelihood | Impact | Mitigation), each Likelihood and Impact Low, Med or High and each mitigation a decision, check or phase"
tags: [design, system-scope, risks, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "design-threads.md holds a Risks thread as a table headed Risk | Likelihood | Impact | Mitigation, with at least one row whose Likelihood and Impact read Low, Med or High and whose mitigation names a design decision, a check or a phase. No .js file is written or edited"
---

/planning:design system

Topic slug `order-notifications`; the Brief is in `.work/order-notifications/PLAN.md`. Run the first discussion round with your recommendations, record the threads in `.work/order-notifications/design/design-threads.md`, then stop for my answers. Don't write any code.
