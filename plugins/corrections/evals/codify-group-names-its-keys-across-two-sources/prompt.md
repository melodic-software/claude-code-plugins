---
description: 'Narration case: it names fictional or consumer-repo paths that no fixture provides.'
tags: ['codify', 'narration']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: 'The skill shows the producer groups with their row and occurrence counts and says they are grouped by producer. It then groups by mistake, says the key is the mistake and the occurrence key is source_id, shows the changelog-fragment group at 2 of 2 and names /corrections:codify for it, shows the git-config group at 1 of 2, and writes nothing.'
---

/corrections:codify group. The settings reader printed {"min_occurrences":2,"layer":"defaults","path":null}. group-findings.mjs printed: `grouped by: producer`, `occurrences: distinct source_id in the group; a row without one counts once`, `2 groups, 3 rows`; `producer="corrections/codify-note": 2 rows, 2 occurrences` with members o1 (ts 2026-10-21T09:00:00Z, source_id #12, signal "the release skipped the changelog fragment") and o2 (ts 2026-10-22T09:00:00Z, source_id #14, signal "a plugin change shipped without a changelog fragment"); `producer="scanner/lint": 1 row, 1 occurrence` with member o3 (ts 2026-10-22T10:00:00Z, source_id 5be7712, signal "a test reads the user's real git config").
