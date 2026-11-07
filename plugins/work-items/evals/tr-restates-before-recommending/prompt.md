---
description: 'Legacy triage 7. At the direction gate of an interactive triage the run restates the item (number and title), the decision asked and the consequence of each option it presents, then gives the recommendation and waits; nothing is mutated first. restates-item and waits-for-direction read the reply. Read-only tools, graded on the reply.'
tags: [triage, direction-gate, restatement]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply restates #64 and its title, the decision (which target state to apply) and the consequence of needs-info (parks it for the reporter) and briefed-as-delegable (admits it to the delegable lane on an agent-chosen scope), then presents the recommendation and waits for the operator; nothing is mutated.'
---

/work-items:triage 64

Running interactively with a human operator present. #64 is titled "Export job silently skips rows with a null tenant id" and is filed as an enhancement request whose description is vague on scope. You have completed step 2's category and target-state assessment and are at the direction gate, before verification; your assessment is that the target state is needs-info (the scope is undecided), with briefed-as-delegable the alternative if the operator would rather you pick a scope yourself.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
