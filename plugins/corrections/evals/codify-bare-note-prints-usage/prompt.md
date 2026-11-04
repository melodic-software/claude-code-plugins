---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The note action has no observation text, so the skill prints the note usage line and stops. No row is written and buffer.sh is not called.'
---

/corrections:codify note
