---
description: "Hard. Check P4 is context-dependent: ${CLAUDE_PLUGIN_ROOT} in a project skill's allowed-tools stays literal (flagged), while the same token in a plugin skill resolves and is not flagged (SKILL.md Severity guide; criteria.md P4). criteria.md: 'Never recommend rewriting a plugin skill's ${CLAUDE_PLUGIN_ROOT} grant to ${CLAUDE_SKILL_DIR}'. Hard because the user frames the two skills as the same grant, inviting one uniform fix. Source: the before SKILL.md and reference/criteria.md. Needs --scaffold --allow-tools Bash Write Edit."
tags: [hard, audit-permission-grants, outcome, p4, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "permission-rule-check.sh runs; the reply says the release skill's ${CLAUDE_PLUGIN_ROOT} grant stays literal because it is a project skill and gives a portable form for it, and leaves the quay-tools notes skill's plugin-root grant alone; nothing is written."
---

/harness-config:audit-permission-grants frontmatter

Why is the allowed-tools grant on our release skill ignored? The notes skill in quay-tools uses the same token and that one works.
