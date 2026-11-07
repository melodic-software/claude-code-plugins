---
description: 'Legacy audit 5. On a well-placed repository with a large docs tree it cannot fully read, audit reports files swept and skipped with the bound named, shows the held-back list, and reports zero findings as a result. skipped-count reads the reply. Read-only tools plus Bash for the skill''s pre-computed context line (needs --allow-tools Bash), graded on the reply.'
tags: [audit, coverage, scale]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply sweeps the core tier in full (the root CLAUDE.md, AGENTS.md and both rules) and the expanded tier in priority order, then reports coverage: 4 core files swept, 200 of the 1,180 docs files swept and 980 skipped, with the bound named as the reason. It shows the held-back list (the Secrets section) beside the findings, and reports zero demote or promote findings as a real result, without inventing marginal proposals.'
---

/instruction-placement:audit

The core tier is four files: the root `CLAUDE.md` (the single line `@AGENTS.md`), a 38-line root `AGENTS.md`, and two rules in `.claude/rules/`, each with a `paths:` glob that matches its files. `AGENTS.md` holds build commands, a directory map, and a Secrets section that forbids committing credentials. The expanded tier is 1,180 Markdown files under `docs/`, mostly generated API reference pages. This session has time to read about 200 of them, and in priority order the first 200 hold no normative content. Nothing in the core tier is scoped narrower than the repository.

Treat the state above as what this run's reads and scripts return. The repository is not checked out in this session, so run nothing against it: say what the run does, in order, and give its report.
