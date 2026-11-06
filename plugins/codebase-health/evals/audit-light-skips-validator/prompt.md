---
description: "A repository whose default branch sets verification: light in docs/conventions/codebase-health.yaml, with a README naming a Makefile and a tally.toml that do not exist: audit Phase 2 reads the level, dispatches no separate validator, writes the skip token and reports the findings unverified rather than grading them itself. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [codebase-health, audit, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; writes verification: skipped (light); reports the README findings as unverified."
---

/codebase-health:audit --docs-only
