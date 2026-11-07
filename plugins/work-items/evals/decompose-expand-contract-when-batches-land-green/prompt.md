---
description: 'Legacy decompose 5. The user asks to skip expand-contract and put every migrate batch on a shared integration branch although each batch merges green alone: the run keeps expand, migrate, contract, adds no integration branch or integrate-and-verify item, and holds the approval gate. expand-migrate-contract reads the reply for the three steps in order. Read-only tools, graded on the reply.'
tags: [decompose, wide-refactor, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Declines the integration-branch shortcut: the rename stays expand, then one migrate item per consumer batch each landing green on the default branch, then contract, with no shared integration branch and no integrate-and-verify item, since that fallback is only for batches that cannot land green alone. The breakdown is presented for approval and nothing publishes before the user approves.'
---

/work-items:decompose

Rename a persisted column. Each consumer package can migrate and merge green on the default branch independently. Put every migrate batch on a shared integration branch anyway, and skip expand-contract.

The topic is contact-email. Its approved PLAN.md renames the stored column `email` to `contact_email`, read by three consumer packages that deploy separately.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why.
