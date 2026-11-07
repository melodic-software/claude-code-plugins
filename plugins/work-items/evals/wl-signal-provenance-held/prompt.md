---
description: 'Legacy work-loop 22. A candidate carrying provenance: signal is held by the provenance hold and escalated as kind=escalated whatever its agent-ready label; the other candidate is dispatched. signal-names-52 reads the reply. Read-only tools, graded on the reply.'
tags: [work-loop, admission-gate, provenance]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: '#51 is admitted and dispatched. #52 is not admitted: provenance: signal holds it for a person (the provenance hold) whatever its other labels say, so step 5 escalates it as kind=escalated and the report names #52 as human-gated by its provenance: signal label.'
---

/work-items:work-loop --drain --single-pass

GitHub binding. Two candidates reach the admission gate, neither with an open closing PR, and label-provenance reports every label applied by a maintainer with write permission. #51 carries agent-ready and is a bug-fix-shaped change to a date parser. #52 carries agent-ready and provenance: signal; it was filed by a queue-depth alert and is also a bug-fix-shaped change.

Treat the state above as what this cycle's reads return. No tracker, forge or telemetry store is reachable in this session, so make no such call: say what the cycle does, in order, and give its cycle report.
