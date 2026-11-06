---
description: "A repository whose default branch sets verification: light gets no refutation verifier in a repo-mode batch-simplify run, where standard makes it mandatory; each group's Verification cell carries the skip token while the final cross-ecosystem pass still runs"
tags: [batch-simplify, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/code-tidying.yaml at origin/main, dispatches no refutation verifier, writes verification: skipped (light) in the group's Verification cell, and still runs the final test pass"
---

I authorize this repo-mode run: run it without stopping to confirm.

/code-tidying:batch-simplify repo in-place --unattended
