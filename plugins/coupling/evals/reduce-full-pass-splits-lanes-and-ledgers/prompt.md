---
tags: ['reduce']
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Verifies both findings against the tree, applies the magic-string reduction (named constant or type) as a budgeted behavior-preserving batch on a short-lived branch with build/test verification, routes the shared-database finding to a human as an architectural candidate without editing schema or services, and records both in the coupling ledger with statuses.'
---

/coupling:reduce

This repo has a magic status string compared in eleven call sites, and its two web services share one database table that both write.
