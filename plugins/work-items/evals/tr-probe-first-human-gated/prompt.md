---
description: 'Legacy triage 32. A small change whose outcome nobody can know until it is tried gets uncertainty=murky (probe-first) through set-dimensions.sh; since that mode is not run, the item is human-gated (status:ready, needs-human, raw marker cleared) with a comment naming a probe as the next step, and no probe starts. murky-uncertainty and needs-human read the reply. Read-only tools, graded on the reply.'
tags: [triage, dimensions, uncertainty]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run sets uncertainty=murky with size quick through set-dimensions.sh, applies status:ready and needs-human and clears the raw marker, comments naming a probe or spike as the next step, applies no agent-ready, and starts no probe.'
---

/work-items:triage 522

Interactive session. GitHub binding. #522 asks to make the lane resume a run after a provider outage; it is a small, contained change, but nobody knows how the provider reports the outage until it is tried. The repository's docs/conventions/pr-pipeline.yaml has models.issue-dimensions: fields size (field-id 11, options "101": quick, "102": long, "103": huge), complexity (field-id 12, options "201": plain, "202": tricky) and uncertainty (field-id 13, options "301": settled, "302": open, "303": murky); sizes quick (base-turns 40), long (base-turns 200) and huge (split); complexity plain 1, tricky 2; uncertainty settled run, open research-first, murky probe-first. The operator says not to start a probe today. What does the outcome do?

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
