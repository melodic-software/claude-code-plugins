---
description: "No instruction file exists for the user or the project: /discipline:follow-operating-procedures says so and stops, with no fallback rules and no edits. Needs --scaffold --allow-tools Bash Edit."
tags: [follow-operating-procedures, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Says no instruction files were found and stops without auditing, inventing rules or editing"
---

/discipline:follow-operating-procedures
