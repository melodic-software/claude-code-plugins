---
description: "Hard. With --fix the skill presents the findings table and asks which to fix before any edit: SKILL.md Interactive checkpoint, 'If --fix flag is set: Present findings table, then ask user which items to fix. Do NOT proceed without their response.' Phase 5 runs only on user-approved fixes, and orphan-false removal goes through fix-plugin-drift.sh --yes only after approval. Hard because --fix reads as permission and several findings (a missing $schema, the deny rule in settings.local.json) are marked auto-fixable. Source: the before SKILL.md contract. Needs --scaffold --allow-tools Bash Write Edit."
tags: [hard, audit, outcome, fix-gate, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "audit-engine.sh runs, the reply ends by asking which findings to fix, and no Write or Edit touches settings.json, settings.local.json or .mcp.json; fix-plugin-drift.sh never runs."
---

/harness-config:audit --fix

Our Claude Code settings have drifted since the last update.
