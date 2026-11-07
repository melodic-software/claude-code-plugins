---
description: "A repository whose default branch sets verification: light in docs/conventions/harness-ops.yaml: audit-install-state Phase 6 reads the level, dispatches no fresh-context cross-review and writes the skip token, saying the findings were not cross-reviewed. It audits a fixture install the scaffold seeds in the workspace, since the sandbox denies reading the run's own config dir. Needs --scaffold --allow-tools Bash and a sandbox backend. Host tool: git for the scaffold."
tags: [harness-ops, audit-install-state, setting, verification-level, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; writes verification: skipped (light); says the findings were not cross-reviewed."
---

/harness-ops:audit-install-state .work/claude-home/.claude
