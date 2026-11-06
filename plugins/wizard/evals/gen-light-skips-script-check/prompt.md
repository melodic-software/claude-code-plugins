---
description: "A repository whose default branch sets verification: light in docs/conventions/wizard.yaml: generate Phase 3 step 2 reads the level, dispatches no fresh-context read of the script, and tells the user at the approval gate verification: skipped (light). Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [wizard, generate, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; dispatches no subagent; writes verification: skipped (light) at the approval gate."
---

/wizard:generate a setup wizard that asks for MAIL_API_TOKEN and writes it to .env. Nothing goes to CI.
