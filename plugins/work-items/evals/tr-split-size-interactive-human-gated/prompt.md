---
description: 'Legacy triage 33. In an interactive session, thirty separate doc rewrites also get the split size through set-dimensions.sh and the same human-gated edit (status:ready, needs-human, raw marker cleared) with a comment naming /work-items:decompose, which is not run. split-size and names-decompose read the reply. Read-only tools, graded on the reply.'
tags: [triage, dimensions, split]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run sets size=huge with the other two dimensions through set-dimensions.sh, applies status:ready and needs-human and clears the raw marker, comments naming /work-items:decompose as the next step, applies no agent-ready, and does not run decompose.'
---

/work-items:triage 523

Interactive session. GitHub binding. #523 asks to rewrite the docs of all thirty plugins to a new template, each a separate change; the approach is clear and the item is otherwise fully specified. The repository's docs/conventions/pr-pipeline.yaml has models.issue-dimensions: fields size (field-id 11, options "101": quick, "102": long, "103": huge), complexity (field-id 12, options "201": plain, "202": tricky) and uncertainty (field-id 13, options "301": settled, "302": open, "303": murky); sizes quick (base-turns 40), long (base-turns 200) and huge (split); complexity plain 1, tricky 2; uncertainty settled run, open research-first, murky probe-first. The operator says not to decompose it today. What does the outcome do?

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
