---
description: 'Legacy triage 28. An invalid repository value (triage_repro_count: 0) is named with its file, key and value, the repository layer is dropped, the key takes the manifest default from layer default, and the triage goes on. The legacy case also set a per-user 4 that must not be taken; a run cannot set that option, so that half is held. settings-repro and names-invalid read the reply. Read-only tools, graded on the reply.'
tags: [triage, settings, invalid-value]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply names docs/conventions/work-items.yaml, triage_repro_count and 0 as invalid, drops that layer without stopping, reports triage_repro_count=2 (default) in the Settings line, and goes on to gather context and attempt reproductions.'
---

/work-items:triage 221

Autonomous lane whose standing directive authorizes triage label and comment mutations. #221 is a raw bug report: 'invoice PDF repeats the footer on every page'. The repository's docs/conventions/work-items.yaml sets triage_repro_count: 0.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
