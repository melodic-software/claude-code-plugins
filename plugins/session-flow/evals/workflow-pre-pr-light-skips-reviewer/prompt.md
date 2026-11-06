---
description: "A repository whose default branch sets verification: light gets no fresh-context reviewer in pre-PR step 2; the self-review still runs and the report carries the skip token"
tags: [workflow, pre-pr, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/session-flow.yaml at origin/main, self-reviews the branch diff, dispatches no reviewer, and notes verification: skipped (light)"
---

/session-flow:workflow pre-pr walk this branch through the pre-PR sequence up to, not including, opening the PR
