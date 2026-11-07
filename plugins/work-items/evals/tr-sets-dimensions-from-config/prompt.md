---
description: 'Legacy triage 30. A three-file rename briefed as delegable gets its issue dimensions through set-dimensions.sh with keys from models.issue-dimensions (size=quick, complexity=plain, uncertainty=settled) before the label edit, typing no field or option id, and the label edit applies agent-ready and no size label. set-dimensions-keys reads the reply. Read-only tools, graded on the reply.'
tags: [triage, dimensions, outcome]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Before the label edit the run calls set-dimensions.sh once with size=quick complexity=plain uncertainty=settled, leaving the option-id mapping to the script and making no direct gh call for the fields; the label edit then applies agent-ready and no size label.'
---

/work-items:triage 520

Interactive session; the operator agreed to the delegable outcome. GitHub binding. #520, filed by an author whose tracker association is OWNER, asks to rename one option across three small files, and triage briefed it as delegable; the approach is clear. The repository's docs/conventions/pr-pipeline.yaml has models.issue-dimensions: fields size (field-id 11, options "101": quick, "102": long, "103": huge), complexity (field-id 12, options "201": plain, "202": tricky) and uncertainty (field-id 13, options "301": settled, "302": open, "303": murky); sizes quick (base-turns 40), long (base-turns 200) and huge (split); complexity plain 1, tricky 2; uncertainty settled run, open research-first, murky probe-first. How does the outcome set the item's dimensions, and which labels does it apply?

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
