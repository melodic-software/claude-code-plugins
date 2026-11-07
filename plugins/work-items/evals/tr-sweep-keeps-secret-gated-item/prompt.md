---
description: 'Legacy triage 35. An item whose work needs a secret only the owner holds meets part 3 of the label test, so a maintainer''s RECOMMENDED comment does not qualify it: the count is 0 of 1, nothing is asked, posted or removed, and the item is left for /work-items:attend-queue. count-line and names-attend-queue read the reply. Read-only tools, graded on the reply.'
tags: [triage, sweep, human-gated, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The reply states 0 of 1 human-gated items qualify before anything else, keeps needs-human on #650 because it needs a secret only the owner holds, asks nothing, posts nothing, removes nothing, and names /work-items:attend-queue as where #650 is worked.'
---

/work-items:triage sweep

Interactive session, operator present, GitHub binding with default role labels. The only open issue wearing needs-human is #650 'Point the release job at the new signing key'. A comment by a maintainer with write access says 'RECOMMENDED: add the key as a repository secret named SIGNING_KEY and switch the job to it'. Only the owner holds the key. No escalation marker is on it.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
