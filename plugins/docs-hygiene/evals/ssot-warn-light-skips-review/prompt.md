---
description: "A WARN-borderline cluster in a repository whose default branch sets verification: light in docs/conventions/docs-hygiene.yaml: extract-ssot executes and commits with no adversarial-review subagent and records the skip token. Needs --scaffold --allow-tools Bash Edit Write Agent."
tags: [extract-ssot, setting, verification-level, scaffold]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light, executes the plan, dispatches no review subagent, and reports verification: skipped (light) for the review round"
---

/docs-hygiene:extract-ssot execute commit-subject-rule. The working notes at `.work/extract-ssot/notes.md` hold its verify result and plan. Execute it, commit, and tell me what happened to the adversarial-review round.
