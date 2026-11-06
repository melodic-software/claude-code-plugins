---
description: "A repository whose default branch sets verification: light in docs/conventions/wizard.yaml: generate Phase 3 step 2 reads the level, diffs the library above the STAGES marker against template.sh, still dispatches the fresh-context subagent for the two secrets items, and tells the user at the approval gate verification: skipped (light) for the rest. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [wizard, generate, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; runs the library diff; dispatches a subagent for the secrets items only; writes verification: skipped (light) at the approval gate."
---

/wizard:generate a setup wizard that asks for MAIL_API_TOKEN and writes it to .env. Nothing goes to CI.
