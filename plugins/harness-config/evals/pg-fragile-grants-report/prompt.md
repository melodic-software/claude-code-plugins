---
description: "Routine. The grants audit runs scripts/permission-rule-check.sh (SKILL.md Phase 1) and reports each fragile grant with its recommendation (Phase 2). The quay grants fixture seeds Bash(python3 *) (P1), a user-home release.sh path (P2, built at scaffold time), and a bundled plugin settings.json that self-grants (P3). Report-only: no settings or skill file is written. Source: the before SKILL.md and reference/criteria.md. Needs --scaffold --allow-tools Bash Write Edit."
tags: [routine, audit-permission-grants, outcome, report-only, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "permission-rule-check.sh runs; the reply names the python3 interpreter wildcard, the machine-specific release.sh grant and the quay-tools plugin settings.json self-grant; nothing is written to settings or skill files."
---

/harness-config:audit-permission-grants

A teammate says some of our Claude Code allow rules don't work on their machine. Can you check them?
