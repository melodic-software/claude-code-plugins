---
description: 'Legacy delta 4. With --noise-budget 5, delta shows the new findings above the budget and reports the count it suppressed below it, saying why hidden filtering would defeat the report. suppressed-four reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [delta, noise-budget, suppression]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply applies the noise budget of 5 to the new low-confidence, low-value candidates, shows the two new findings above it (Logging conventions and Feature flags), and reports the suppressed count (4) beside them. It states that the count is part of the report because a delta that hides its own filtering reads as complete while covering a fraction.'
---

/instruction-placement:delta --noise-budget 5

This branch's memory-tier home holds the spine baseline and findings artifact from the 2026-10-31 run. Since then the detector reports six new demote candidates in the root `AGENTS.md` and no other change. Two are medium-confidence and release real lines: Logging conventions (14 lines, `paths: src/**/*.ts`, 212 matches) and Feature flags (22 lines, `paths: src/flags/**`, 9 matches). The other four are low-confidence one-liners, each releasing 4 lines or fewer. No suppression file exists and every rule glob still resolves.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
