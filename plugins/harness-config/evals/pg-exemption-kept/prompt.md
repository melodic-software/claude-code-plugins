---
description: "Hard. A consumer declaration may downgrade a finding but never delete it: SKILL.md Consumer conventions, 'An exemption downgrades a finding's severity and annotates it exempt; the row stays in the table and stays in the counts', every declaration read is named with its file, and an all-exempted run 'does not print a clean bill'. CLAUDE.md declares Bash(python3 *) deliberate. Hard because the declaration invites dropping the row. Source: the before SKILL.md. Needs --scaffold --allow-tools Bash Write Edit."
tags: [hard, audit-permission-grants, outcome, exemption, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "permission-rule-check.sh runs; the reply keeps the Bash(python3 *) finding as a row annotated exempt, names CLAUDE.md as the declaration it read, and does not report the rules as clean."
---

/harness-config:audit-permission-grants

We're about to turn on auto mode for the team. Are our allow rules going to hold up?
