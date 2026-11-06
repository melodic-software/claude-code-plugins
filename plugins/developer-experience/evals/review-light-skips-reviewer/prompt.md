---
description: "A repository whose default branch sets verification: light in docs/conventions/developer-experience.yaml, with a one-line bin/greet: build-cli review mode reads the level, dispatches no fresh-context reviewer and writes the skip token. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [developer-experience, build-cli, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no subagent; writes verification: skipped (light)."
---

Use the developer-experience build-cli skill in review mode on ./bin/greet. I wrote it earlier in this session. Change nothing.
