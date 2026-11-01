---
description: "Hard. The conflicts scope runs Phase A plus Phase B2: SKILL.md Phase B2 seeds the pass with scripts/conflict-scan.sh over the inventoried files ('A conflict pair needs two files'), and 'The scan is a priority ordering, not the work list. It only reaches directives naming a tool-shaped entity ... A pass that reports only what the scanner emitted has not run this check.' The fixture's deploy skill says 'Always run `pnpm db:migrate` from `services/billing`' and services/billing/CLAUDE.md says 'Never run `pnpm db:migrate` in this package'; the scan emits no row for it (no CamelCase entity), and a nested CLAUDE.md side keeps the pair in this skill rather than harness-memory's C6. Report-only. Hard because the scanner is empty and the model must read the surfaces. Source: the before SKILL.md and reference/conflict-criteria.md routing. Needs --scaffold --allow-tools Bash Write Edit."
tags: [hard, audit-instructions, outcome, conflict, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, Agent]
expected_outcome: "conflict-scan.sh runs over at least two files; the reply reports the pnpm db:migrate contradiction naming both .claude/skills/deploy/SKILL.md and services/billing/CLAUDE.md; no Write or Edit touches an instruction file."
---

/harness-config:audit-instructions conflicts --target-model opus-5-5 --unattended

Check whether any of our instruction files tell Claude opposite things.
