---
description: 'Legacy triage 4. The briefed-and-delegable outcome removes needs-triage in the same edit that applies status:ready and the autonomous-eligible role label: the outcome replaces the raw marker rather than stacking on it. The legacy prompt called #42 an external report, which the current skill marks provenance: untrusted and human-gates, so the reporter here is an org member. clears-raw-marker reads the reply. Read-only tools, graded on the reply.'
tags: [triage, outcome, raw-marker]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'One label edit applies status:ready and the autonomous-eligible role label and removes needs-triage, and the reply states that an open item never carries the raw marker beside a briefed, ready or role label, which the attention view would re-select every cycle.'
---

/work-items:triage 42

Item #42 is a bug report filed by an org member (the tracker reports its author association as MEMBER), currently tagged needs-triage; you have verified it and are ready to brief it for autonomous pickup. The operator has said to go ahead.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
