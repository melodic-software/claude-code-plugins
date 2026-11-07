---
description: 'Legacy work-loop 20. A scheduled --drain --single-pass run whose first cycle executes two items, reaching item_cap 2, ends the run with no ScheduleWakeup, no --single-pass in durable state and no drain-complete claim. no-wakeup reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, single-pass, drain]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The two executed items reach the item cap, so the single pass ends: the cycle upserts telemetry, the report names the item cap as what ended the run and lists the two items still open, no ScheduleWakeup is called, --single-pass is not written into durable state, no restart-request is written, and the drain is not reported complete.'
---

/work-items:work-loop --drain --single-pass

Started headless by a scheduler with claude -p. The resolved item_cap is 2. The cycle-start snapshot holds four autonomous-frontier items, all C2 mechanical with no open closing PR. The first cycle executes two of them to opened PRs.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
