---
description: 'Legacy triage 21. The label preflight finds status: confirmed absent, so the run stops without mutating: it creates no label, substitutes none, keeps the raw marker, and reports a provisioning gap. provisioning-gap reads the reply. Read-only tools, graded on the reply.'
tags: [triage, preflight, hard-stop, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run stops before any write: it does not create status: confirmed, applies no other label in its place, leaves #216 unmutated with its raw marker, and reports the missing label as a provisioning gap for the label-as-code owner or a person.'
---

/work-items:triage 216

Autonomous lane whose standing directive authorizes triage label and comment mutations. #216 is a raw bug report that reproduces twice on the default branch. The repository's label list has no status: confirmed label.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
