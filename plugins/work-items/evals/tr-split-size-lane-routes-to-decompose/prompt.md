---
description: 'Legacy triage 31. In a lane, forty separate plugin changes fit no size''s base-turns, so the split size is set through set-dimensions.sh; the item is human-gated (status:ready, needs-human, raw marker cleared) with a comment naming /work-items:decompose, and the lane runs no decompose itself. split-size and names-decompose read the reply. Read-only tools, graded on the reply.'
tags: [triage, dimensions, split, lane]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run sets size=huge with the other two dimensions through set-dimensions.sh, applies status:ready and needs-human and clears the raw marker, comments naming /work-items:decompose as the next step, applies no agent-ready, and neither runs decompose nor creates child items.'
---

/work-items:triage 521

Running autonomously as the triage lane; its standing directive authorizes triage label and comment mutations. GitHub binding. #521 asks to migrate every plugin's hooks to a new event format, about forty plugins, each a separate change; the approach is clear and the item is otherwise fully specified. The repository's docs/conventions/pr-pipeline.yaml has models.issue-dimensions: fields size (field-id 11, options "101": quick, "102": long, "103": huge), complexity (field-id 12, options "201": plain, "202": tricky) and uncertainty (field-id 13, options "301": settled, "302": open, "303": murky); sizes quick (base-turns 40), long (base-turns 200) and huge (split); complexity plain 1, tricky 2; uncertainty settled run, open research-first, murky probe-first. What does the outcome do?

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
