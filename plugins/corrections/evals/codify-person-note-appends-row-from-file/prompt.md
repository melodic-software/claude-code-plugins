---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The first word is the unquoted action note, so the skill composes one row with producer corrections/codify-note and source_id 3f2a1bc, writes it with the Write tool under .work/codify/notes/, runs buffer.sh append with that file and reports the result. It does not count, pick a rung, propose a check or edit code.'
---

/corrections:codify note "handlers build SQL by string concatenation" 3f2a1bc
