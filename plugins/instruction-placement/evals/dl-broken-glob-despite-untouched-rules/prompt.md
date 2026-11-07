---
description: 'Legacy delta 3. Told nothing touched the rules folder, delta re-validates every previously valid glob anyway, reports the one a refactor broke as broken-glob, and explains that a rename elsewhere breaks a glob with no signal. payments-broken-glob reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [delta, broken-glob, cadence]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply re-validates every glob the baseline recorded valid, whatever the operator says about the rules folder, and reports .claude/rules/payments.md (src/payments/**/*.ts, 41 matches at baseline, 0 now) as broken-glob. It explains why the premise does not make the check unnecessary: a glob breaks when the code it described is renamed or moved, an ordinary refactor nowhere near the rules tree, with no signal at the time, leaving the rule silently not firing, which is why delta runs on a cadence.'
---

/instruction-placement:delta nothing touched the rules folder this sprint.

This branch's memory-tier home holds the spine baseline and findings artifact from the 2026-10-24 run. The baseline records two rules: `.claude/rules/payments.md` with `src/payments/**/*.ts` (41 matches, `valid`) and `.claude/rules/sql.md` with `db/**/*.sql` (37 matches, `valid`). This sprint's commits changed nothing under `.claude/`; one of them moved `src/payments/` to `src/billing/`. Today `glob-tools.sh rules` reports `src/payments/**/*.ts` with 0 matches and `db/**/*.sql` with 37. No section changed and no new candidate appears.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
