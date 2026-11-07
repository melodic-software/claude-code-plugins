---
description: 'Legacy triage 11. A named triage of an issue titled `Lane telemetry: work-loop` reports it as lane infrastructure by the title contract and stops: no state machine, no recommendation, no label edit, note or close. tr-pinned-telemetry-not-triaged covers the pinned-config route; this case covers the default-title route. lane-infrastructure reads the reply. Read-only tools, graded on the reply.'
tags: [triage, lane-telemetry, hard-stop, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply identifies #1248 as lane infrastructure by its Lane telemetry: <lane> title, not by its labels, and stops without verifying, recommending, relabeling, commenting or closing, because the lane reads that surface to operate.'
---

/work-items:triage 1248

Item #1248 is titled `Lane telemetry: work-loop` and carries `needs-triage`.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
