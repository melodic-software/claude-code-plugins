---
description: "Bare scan is read-only: the skill reports all three issue references as untracked and points at scan --add, and never adds to the registry by script, Write, Edit or shell write. Reaches SKILL.md 'Action Router' (the scan row: read-only unless --add) and the scan spoke. Needs --scaffold --allow-tools Bash Write Edit."
tags: [harness-ops, known-issues, outcome, read-only]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The reply lists anthropics/claude-code #41234 and #50871 and microsoft/mcp #1187 as untracked and tells the user to run scan --add to register them. No registry_manager.py add/update/remove call and no write to registry.json."
---

/harness-ops:known-issues scan
