---
description: "A repository whose default branch sets verification: light dispatches no plan-reviewer in Step 3; the plan's review record carries the skip token"
tags: [plan, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/planning.yaml at origin/main, drafts the plan, dispatches no planning:plan-reviewer, and writes verification: skipped (light) in the review record"
---

/planning:plan add a max_length argument to slugify that truncates on a word boundary
