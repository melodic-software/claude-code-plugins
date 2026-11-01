---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The proposal names the rung and the check, and also answers what the model did not have in front of it when it made the mistake: the pricing rules file, which was never opened. The answer sits next to the rung so the fix can be context as well as a check.'
---

/corrections:codify "a null price reached checkout and charged zero" - this defect escaped review twice (commits c04e8d1 and 7ad3f90) and codify this. The pricing rules file was never opened in either session.
