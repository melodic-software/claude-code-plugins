---
description: "A WARN-borderline cluster in a repository whose default branch sets verification: standard in docs/conventions/docs-hygiene.yaml: extract-ssot runs the adversarial-review round as a fresh-context diff review before commit. Needs --scaffold --allow-tools Bash Edit Write Agent."
tags: [extract-ssot, setting, verification-level, scaffold]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: standard, executes the plan, and dispatches a fresh-context diff review before the commit; writes no skip token"
---

/docs-hygiene:extract-ssot execute commit-subject-rule. The working notes at `.work/extract-ssot/notes.md` hold its verify result and plan. Execute it, commit, and tell me what happened to the adversarial-review round.
