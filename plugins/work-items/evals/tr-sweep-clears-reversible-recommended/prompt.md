---
description: 'Legacy triage 34. The attended human-gated sweep counts first (1 of 3 fail the label test and carry a recommendation), keeps the label on the irreversible publish and the item with no recommendation, asks once, and on yes posts the Decision defaulted comment before removing needs-human from #640, applying no other label. count-line and decision-defaulted read the reply. Read-only tools, graded on the reply.'
tags: [triage, sweep, human-gated]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply states 1 of 3 human-gated items fail the label test and carry a recommendation, lists #640 with where its RECOMMENDED line is, keeps #641 (irreversible publish) and #642 (no recommendation), asks once, then posts on #640 a comment with a Decision defaulted line, its Basis line, the failed label test and a link to the recommendation before removing needs-human, applying no other label and changing nothing on #641 or #642.'
---

/work-items:triage sweep

Interactive session, operator present, GitHub binding with default role labels, no objection window configured. Open issues wearing needs-human: #640 'Rename the --out flag to --output', whose body (written by the owner, who holds admin) ends 'RECOMMENDED: rename it and keep --out as a deprecated alias'; the change is reversible and touches one plugin. #641 'Publish the 2.0 package to the public registry', whose body has a RECOMMENDED line from the owner. #642 'Pick a logging format', with no recommendation anywhere. None carries an escalation marker or an earlier sweep comment. The operator answers yes when asked.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
