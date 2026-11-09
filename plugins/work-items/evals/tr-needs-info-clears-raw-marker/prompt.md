---
description: 'Legacy triage 5. The needs-info outcome removes needs-triage in the same edit that applies needs-reporter-info, and the item re-enters the attention view through the needs-info-reply bucket when the reporter answers. clears-raw-marker and needs-info read the reply. Read-only tools, graded on the reply.'
tags: [triage, outcome, raw-marker, needs-info]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'One edit applies needs-reporter-info with the structured needs-info comment and removes needs-triage; the reply says the item comes back through the needs-info-reply bucket on the reporter''s reply, not through the raw-marker bucket every cycle.'
---

/work-items:triage 42

Item #42 is an external bug report currently tagged needs-triage; the description is too thin to reproduce and you are marking it needs-info. The operator has said to go ahead.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
