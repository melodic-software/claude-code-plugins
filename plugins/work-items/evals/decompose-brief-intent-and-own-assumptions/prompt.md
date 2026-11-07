---
description: 'Legacy decompose 12. Plain items from a Brief with Problem, Goal and its Intent, Vision and When-goals-conflict lines, plus a load-bearing assumptions table: every body copies the Problem and Intent, and each item carries only the assumption row it depends on. intent-quote reads the reply for the Intent line''s quoted words. Read-only tools, graded on the reply.'
tags: [decompose, intent-chain, hard]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Publishes two items. Each body copies the Brief''s Problem (shift trades by text leave the printed roster wrong) and the Goal with its Intent, Vision and When-goals-conflict lines. The swap-flow item''s Load-bearing assumptions table holds only the app-account row; the printed-roster item''s holds only the nightly-snapshot row. No body names a memory-root path.'
---

/work-items:decompose

The topic is shift-swap. Its approved PLAN.md Brief has `### Problem`: nurses trade shifts by text message, so the roster the charge nurse prints is wrong most mornings. Its `### Goal`: swaps happen inside the scheduling app. `- Intent (why, in the user's words): "the printed roster should be right without anyone phoning around"`, `- Vision (where this heads): every roster change goes through one place`, `- When goals conflict, prefer: a correct roster over a fast swap`. Under `## Plan` its `### Load-bearing assumptions` table has two rows: `Every nurse has an app account | staffing export | count accounts against the staff list | invite the missing nurses first` and `The roster printer reads the app's nightly snapshot | ward IT note | print after a trial swap | add a refresh before printing`. Phase 1 is the swap request and approval flow, which depends on the first row only; Phase 2 is the printed roster reflecting approved swaps, which depends on the second row only. The repository is public. Publish the breakdown as plain items with no spec container; I approve it in advance.

Treat the state above as what this run's reads return, and the operator's answers as given above. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does, in order, and why, and show each item body as it would be published.
