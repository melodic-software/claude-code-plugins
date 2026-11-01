---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The skill drops the September row by its ts, groups the two October SQL rows as one mistake at 2 of 2 (at the threshold) and names /corrections:codify with the SQL concatenation mistake, shows the auth group at 1 of 2, and writes nothing, appends nothing and runs no proof or codify step.'
---

/corrections:codify group --since 2026-10-01T00:00:00Z. The settings reader printed {"min_occurrences":2,"layer":"defaults","path":null}. buffer.sh read returned four rows: (a) obs_id o1, source_id 3f2a1bc, ts 2026-10-03T09:00:00Z, signal "handlers build SQL by string concatenation"; (b) obs_id o2, source_id 91ac0de, ts 2026-10-10T09:00:00Z, signal "a handler concatenates user input into a SQL string"; (c) obs_id o3, source_id 5be7712, ts 2026-10-12T09:00:00Z, signal "new endpoints skip the shared auth helper"; (d) obs_id o4, source_id c04e8d1, ts 2026-09-12T08:00:00Z, signal "handlers build SQL by string concatenation".
