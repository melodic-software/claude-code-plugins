---
description: "System-scope design whose production Brief records three quality requirements with targets (60 s at p95, no loss while the provider is down, 50 orders per second): the first round writes each as a six-part quality scenario (source, stimulus, artifact, environment, response, measure) in design-threads.md, measures quoted from the Brief, and asks none of them again"
tags: [design, system-scope, quality-scenarios, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "design-threads.md holds a Quality scenarios thread whose rows carry source, stimulus, artifact, environment, response and measure, one per Brief quality requirement, the measures quoting the Brief's targets (60 s at p95, within 1 hour of recovery, 50 orders per second). The reply asks no question that re-opens those targets. No .js file is written or edited"
---

/planning:design system

Topic slug `order-notifications`; the Brief is in `.work/order-notifications/PLAN.md`. Run the first discussion round with your recommendations, record the threads in `.work/order-notifications/design/design-threads.md`, then stop for my answers. Don't write any code.
