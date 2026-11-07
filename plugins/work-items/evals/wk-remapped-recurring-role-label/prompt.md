---
description: 'Legacy work 2. With recurring-maintenance remapped to scheduled-upkeep, the run resolves the label first, excludes scheduled-upkeep items from the frontier tiers and queries --label scheduled-upkeep for the recurring cross-reference, never the default literal. label-scheduled-upkeep reads the reply. Read-only tools, graded on the reply.'
tags: [work, role-labels, recurring]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run resolves recurring-maintenance to scheduled-upkeep before any tracker read, excludes scheduled-upkeep items from the non-recurring frontier tiers, cross-references recurring candidates with --label scheduled-upkeep, and never compares against or queries the default recurring literal.'
---

/work-items:work

The tracker binding maps recurring-maintenance to scheduled-upkeep. Both due maintenance and ordinary frontier items exist.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
