---
description: "A repository whose default branch sets verification_skills.implement: light gets no fresh-context phase verifier for a behavior-changing phase, and the plan mark carries the skip token instead of a verdict the session rendered itself"
tags: [implement, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/implementation.yaml at origin/main, implements the discount, dispatches no verifier for the phase, and writes verification: skipped (light) where the verdict would go"
---

/implementation:implement execute the approved plan at .work/discount/PLAN.md, inline. The plan is approved, and committing on the current branch is allowed. Do not push or open a pull request.
