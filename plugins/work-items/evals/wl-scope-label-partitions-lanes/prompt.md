---
description: 'Legacy work-loop 8. Two concurrent lanes on one repository with --scope area:api and --scope area:docs and distinct --instance ids: each filters the snapshot to its label and keeps its own telemetry marker. own-instance-marker reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, scope, concurrency]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The api lane filters the cycle-start snapshot to area:api and sees only #201 and #203; the docs lane sees only #202. Distinct --instance ids keep separate telemetry markers (work-items:work-loop@api-lane and @docs-lane), so durable state does not clobber across lanes. Neither lane works an item outside its scope label.'
---

/work-items:work-loop --scope area:api --instance api-lane

Concurrent sibling lane on the same repository runs with --scope area:docs --instance docs-lane. The frontier holds three autonomous candidates: #201 labeled area:api, #202 labeled area:docs, #203 labeled area:api.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
