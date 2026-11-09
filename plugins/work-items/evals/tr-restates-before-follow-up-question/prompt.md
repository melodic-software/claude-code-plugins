---
description: 'Legacy triage 8. A follow-up scoping question in the same interactive pass carries its own restatement (item, the decision it resolves, and for an open-ended question what the answer will determine instead of a manufactured option list), is posted as an item comment, and the item is marked needs-reporter-info. restates-item and needs-info read the reply. Read-only tools, graded on the reply.'
tags: [triage, restatement, interview, needs-info]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Before posting the scoping question the reply restates #64 and its title and the decision the question resolves, says what the open-ended answer will determine rather than inventing options, posts the question as an item comment and marks #64 needs-reporter-info.'
---

/work-items:triage 64

Running interactively with a human operator present. #64 is an enhancement request titled "Export job silently skips rows with a null tenant id", so the open question is scope, not fact. You already briefed and presented your step-2 recommendation and the operator has replied: "go ahead, park it as needs-info and ask the reporter what you need." You are now at step 4 with the scope still undecided, so a follow-up scoping question for the reporter is the next step.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
