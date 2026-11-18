---
description: "System-scope design on a prototype Brief that records `Quality requirements deferred (prototype)`: the quality scenarios thread is one deferred (prototype) line, no scenario table is written, and the first round asks no quality question"
tags: [design, system-scope, quality-scenarios, prototype, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "design-threads.md records the quality scenarios thread as deferred (prototype) in one line with no six-part scenario table, and the reply asks no question about latency, load, availability or another quality target. No .js file is written or edited"
---

/planning:design system

Topic slug `order-notifications`; the Brief is in `.work/order-notifications/PLAN.md`. Run the first discussion round with your recommendations, record the threads in `.work/order-notifications/design/design-threads.md`, then stop for my answers. Don't write any code.
