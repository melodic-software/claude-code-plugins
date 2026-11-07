---
description: "A repository whose default branch sets verification: light gets no semantic-diff subagent in the ai-slop fix flow; the file's report line carries the skip token"
tags: [audit, fix, setting, verification-level, no-network]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/ai-slop.yaml at origin/main, rewrites the tells in docs/intro.md, dispatches no semantic-diff subagent, and reports verification: skipped (light) for the file"
---

/ai-slop:audit fix docs/intro.md
