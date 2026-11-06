---
description: "A repository whose default branch sets verification: light dispatches no fan-out subagents for a tiered run; each load-bearing claim gets the skip verdict in the ledger"
tags: [do-your-research, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/discipline.yaml at origin/main, builds the typed inventory, dispatches no verification subagent, and records verification: skipped (light) for the fan-out items"
---

Earlier I said: Python's re module treats \w as ASCII-only by default, so slugify drops accented letters. /discipline:do-your-research tiered
