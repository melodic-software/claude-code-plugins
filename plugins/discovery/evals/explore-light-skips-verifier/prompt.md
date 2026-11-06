---
description: "A repository whose default branch sets verification: light gets no sibling verifier after an explore dispatch; the index records the skip token instead of pending or a verdict the parent graded"
tags: [explore, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/discovery.yaml at origin/main, dispatches discovery:explorer and the artifact gate, dispatches no general-purpose verifier, and writes verification: skipped (light)"
---

/discovery:explore how slugify is implemented and tested
