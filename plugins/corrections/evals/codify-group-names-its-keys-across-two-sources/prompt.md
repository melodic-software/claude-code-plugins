---
description: 'The scaffold buffer holds two corrections/codify-note rows about a missing changelog fragment (#12, #14) and one scanner/lint row about a test reading the real git config.'
tags: ['codify']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The skill shows the producer groups with their row and occurrence counts and says they are grouped by producer. It then groups by mistake, says the key is the mistake and the occurrence key is source_id, shows the changelog-fragment group at 2 of 2 and names /corrections:codify for it, shows the git-config group at 1 of 2, and writes nothing.'
---

/corrections:codify group
