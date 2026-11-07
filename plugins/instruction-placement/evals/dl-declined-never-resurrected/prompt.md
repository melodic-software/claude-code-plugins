---
description: 'Legacy delta 2. A finding declined last week whose source section has since changed stays declined: delta reports the real movement, never re-proposes the declined move, and says once why a re-run does not reopen a decision. declined-stands reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [delta, declined, suppression]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply reports the movement (IP-007, Docker conventions, as new) without re-proposing IP-004 in any shape: not as new, not as changed, not for review. It may note that the Testing conventions section changed while leaving the declined status standing and the artifact untouched, and it says once why: a re-run does not reopen a decision, and resurrecting decisions teaches the operator to stop reading the report.'
---

/instruction-placement:delta we declined the 'Testing conventions' move last week, has anything changed?

This branch's memory-tier home holds the spine baseline and findings artifact from the 2026-10-31 run. In the artifact, IP-004 (demote the Testing conventions section of the root `CLAUDE.md` to `.claude/rules/testing.md` with `paths: **/*.test.ts`) has status `declined`. Since that run the Testing conventions section gained two lines about snapshot files. One other section, Docker conventions, is new and the detector reports it as a medium-confidence demote candidate (IP-007, `paths: **/Dockerfile`, 6 matches). Every rule glob still resolves.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
