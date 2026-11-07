---
description: 'Legacy track 5. Republishing an approved PLAN.md to #812, which already holds two comments opening with the planning marker (4410 by the publishing login, 4502 by another account that copied it), edits 4410 in place and ignores 4502. edits-4410 reads the reply. Read-only tools, graded on the reply.'
tags: [track, publish-plan, narration]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The run checks PLAN.md''s Approval: line before any write, writes the marker line, a blank line and the plan text to a file, keeps only marker comments by the publishing login, edits comment 4410 in place from that file, ignores 4502, and posts no new comment.'
---

/work-items:track publish-plan 812 .work/invoice-export/PLAN.md

PLAN.md has an Approval: line. Item #812 already has two comments whose first line is <!-- planning:plan v1 -->: comment 4410 written by my login last week, and comment 4502 written by another account that copied the marker.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does and why.
