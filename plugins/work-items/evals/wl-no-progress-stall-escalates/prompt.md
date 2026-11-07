---
description: 'Legacy work-loop 4. Two dirty executions with no tracker change take no_progress_streak from 2 to 3, the unset threshold''s default, so the lane raises one Lane stall: work-loop escalation and keeps looping. stall-title and streak-reaches-3 read the reply. Read-only tools, graded on the reply.'
tags: [work-loop, no-progress, escalation]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The streak increments to 3, the manifest default threshold, so the lane creates a ''Lane stall: work-loop'' item through the seam create-item verb with the resolved human-gated role label and a lane=work-loop kind=escalated marker comment, after checking for an open one by exact title and write-identity author; the escalation is not progress, the lane keeps looping and persists no_progress_streak 3.'
---

/work-items:work-loop

Cycle end. Durable state: no_progress_streak=2, item_cap=2. The cycle-start snapshot held two autonomous-frontier candidates. Both admitted items executed dirty with failed verdicts and no tracker state change this cycle: no PR opened, no item closed, no item routed or escalated. work_loop_no_progress_threshold is unset. No open item titled 'Lane stall: work-loop' exists.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
