---
description: "Session start, no work yet: /discipline:follow-operating-procedures rereads the project instruction files, edits nothing and reports no findings, because there is nothing to audit. Needs --scaffold --allow-tools Bash Edit."
tags: [follow-operating-procedures, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Reads AGENTS.md, makes no edit, and says there is no work to audit yet"
---

/discipline:follow-operating-procedures
