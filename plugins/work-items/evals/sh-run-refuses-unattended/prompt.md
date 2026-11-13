---
description: 'Legacy ship 9. run invoked from a /loop cycle in a background session with no human attached: it stops before any claim, says run is attended only, and claims, dispatches and merges nothing. says-attended-only reads the reply. Read-only tools, graded on the reply.'
tags: [ship, run, attended-only, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Stops before any claim and reports that run is attended only and has no unattended mode; it claims nothing, dispatches nothing and merges nothing.'
---

/work-items:ship run #360

Invoked from a /loop cycle in a background session; no human is attached. #360 is an open container item labeled spec-container. The container body carries `**Execution shape:** per-item PRs` and two ready sub-items.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
