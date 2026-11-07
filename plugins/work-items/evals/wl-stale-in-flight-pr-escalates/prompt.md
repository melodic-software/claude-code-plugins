---
description: 'Legacy work-loop 10. With work_loop_in_flight_stale_days unset (14), a 30-day-old ready closing PR stops excluding its item silently and escalates it, while a 3-day-old draft stays silently excluded. stale-line and young-in-flight-line read the reply. Read-only tools, graded on the reply.'
tags: [work-loop, admission-gate, in-flight, escalation]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The unset key means 14 days. #320 is not dispatched and is escalated (human-gated label, kind=escalated marker whose question names PR #451, ready, about 30 days, and asks to land, close or unlink it), listed as ''stale in flight: #320 (PR #451, ready, open 30d) -> escalated''. #321 stays silently excluded, listed as ''in flight: #321 (PR #452, draft, open 3d)''. The escalation is not progress.'
---

/work-items:work-loop

Cycle 4 of a drain. work_loop_in_flight_stale_days is unset. The frontier holds two agent-ready candidates. #320 is linked by closedByPullRequestsReferences to open ready PR #451 via 'Closes #320', created 30 days ago. #321 is linked to open draft PR #452, created 3 days ago. No escalation marker exists on either item. Both Open linked PRs queries succeed.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
