---
description: "A closed map issue as the PRD source. Why hard: the newest comment is a short close summary, not the decisions, and the reflex is to ask the decided questions again or to read the tracker with a provider command."
tags: [prd, map-source]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Reads the item through /work-items:track view with --comments, sees it is a closed map, and takes the decisions from the closing comment that states them, not from the later close summary. The primary user, the no-email-alerts non-goal and the 30% within 30 days metric are settled answers the PRD carries and the run does not ask again."
---

/planning:prd consumer #812

Issue #812 is a closed map that /planning:wayfind charted for a saved-searches feature on the jobs board. Its body has Destination, Notes, Decisions-so-far, Not-yet-specified and Out-of-scope sections and no Execution shape line. Its comments, oldest first: a closing comment listing every resolved decision (Q2 'Who is the primary user?': active job seekers who re-run one filter set; Q4 'Do saved searches send email alerts?': no, not in v1; Q5 'What is the success metric?': 30% of returning seekers re-run a saved search within 30 days), then a short close summary 'Destination coherent, handed to /planning:prd.'

Treat these as what the tracker reads return. No tracker is reachable in this session, so make no such call: say which reads the run makes, in order, what it does with them, and which questions it still asks.
