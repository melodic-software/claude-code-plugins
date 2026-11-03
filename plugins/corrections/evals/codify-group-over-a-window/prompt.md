---
description: 'The scaffold buffer holds four rows: two October SQL-concatenation rows, one October auth-helper row and one September SQL row that --since drops.'
tags: ['codify']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The skill drops the September row by its ts, groups the two October SQL rows as one mistake at 2 of 2 (at the threshold) and names /corrections:codify with the SQL concatenation mistake, shows the auth group at 1 of 2, and writes nothing, appends nothing and runs no proof or codify step.'
---

/corrections:codify group --since 2026-10-01T00:00:00Z
