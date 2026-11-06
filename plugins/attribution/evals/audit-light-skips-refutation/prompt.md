---
description: "A repository whose default branch sets verification: light runs no review or refutation pass; a finding that would take one carries the skip token and is never relay-eligible"
tags: [audit, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/attribution.yaml at origin/main, dispatches no refutation or review agent, and marks the affected finding verification: skipped (light)"
---

/attribution:audit docs/http.md
