---
description: 'Legacy triage 25. The objection-window comment goes before the label edit; when its post fails with HTTP 502 the run applies no label edit at all, leaves the raw marker so a later sweep retries, and reports the failed post. reports-failed-post and raw-marker-stays read the reply. Read-only tools, graded on the reply.'
tags: [triage, objection-window, failure, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run attempts the objection-window comment before any outcome label edit; after the 502 it applies no autonomous-eligible role label and no status: ready, leaves needs-triage on #220 for a later sweep, and reports the failed post.'
---

/work-items:triage 220

Autonomous lane whose standing directive authorizes triage label and comment mutations. #220 is a raw bug report that reproduces twice, classifies as a scoped bug fix, and is fully specified. The repository's docs/conventions/work-items.yaml sets triage_objection_window_hours: 12. The verification comment and the brief post, but the request posting the objection window comment fails with HTTP 502.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
