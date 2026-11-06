---
description: "A repository whose default branch sets verification: light dispatches no plan-reviewer in Step 3; the reply that reports Step 3 carries the skip token"
tags: [plan, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/planning.yaml at origin/main, dispatches no planning:plan-reviewer, and states verification: skipped (light) in the reply that reports Step 3"
---

/planning:plan Continue the draft at `.work/slugify-max-length/PLAN.md` from Step 3. The Brief and the design gate are settled; `.work/slugify-max-length/design/design-resolution.md` records the design early exit. Run Steps 3 and 3b as this skill and this repository's settings say, then report what each step did. Stop there: no Step 4 onward, and edit no code.
