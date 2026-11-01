---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The person invoked the skill and said to codify it, so the one-occurrence count is below the threshold of 2 but acts anyway. The report lists the single occurrence with its commit, picks a rung by id from the ladder, places the lesson by scope, proves the check with prove-check.sh, and writes the proposal file under .work/codify/, announcing the path first.'
---

/corrections:codify "handlers build SQL by string concatenation" - codify this now. It has only happened once in the log, in commit 3f2a1bc.
