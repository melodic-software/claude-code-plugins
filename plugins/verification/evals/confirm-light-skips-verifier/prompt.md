---
description: "A repository whose default branch sets verification: light gets no fresh-context verifier and a NOT VERIFIED verdict carrying the skip token, never a CONFIRMED the session rendered itself"
tags: [confirm, setting, verification-level]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/verification.yaml at origin/main, dispatches no verifier, writes verification: skipped (light), and gives the verdict NOT VERIFIED rather than CONFIRMED"
---

/verification:confirm
