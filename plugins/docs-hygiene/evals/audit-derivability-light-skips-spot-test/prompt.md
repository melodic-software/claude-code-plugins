---
description: "A repository whose default branch sets verification: light gets no fresh-context spot-test for a load-bearing delete or convert-to-pointer verdict; the verdict ships provisional with the skip token"
tags: [audit-derivability, setting, verification-level]
runs: 3
max_turns: 60
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light from docs/conventions/docs-hygiene.yaml at origin/main, dispatches no spot-test subagent, and writes verification: skipped (light) on the Spot-test line of a provisional verdict"
---

/docs-hygiene:audit-derivability docs/build.md
