---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The description is quoted, so the first word of the arguments is not the bare word note. The skill runs the default action: it counts occurrences against the threshold and does not treat this as the note action. It writes no buffer row.'
---

/corrections:codify "note fields are dropped on save"
