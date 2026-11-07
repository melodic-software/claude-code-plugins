---
description: 'Legacy work-loop 7. A --drain cycle end where every retained id is closed or covered by an open non-draft closing PR: the drain is complete, so the lane writes its final report and stops, where standing mode would have kept looping. standing-would-continue reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, drain, exit]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'With --drain the lane loads reference/mode-drain.md, evaluates the exit over the cycle-start retained ids, finds the drain complete, writes the final report, persists stop_mode=drain and stops cleanly. A standing invocation would report and ScheduleWakeup the next cycle.'
---

/work-items:work-loop --drain

Cycle end. stop_mode=drain. The filtered cycle-start snapshot shows every retained id either closed or covered by an open non-draft close-linked PR.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
