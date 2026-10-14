---
description: "Hand-tallied counts in a summary (route total, POST count, allowlist adds and drops) are wrong. The run must compute them with a command, not by reading, and restate the corrected figures from the command output"
tags: [discipline, script-the-deterministic-work, outcome, scaffold]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash, Edit]
expected_outcome: "At least one Bash call runs a counting or set tool (grep, wc, diff, comm, sort, a script); the reply states 13 routes, 6 POST, 3 hosts added, and reports.internal dropped."
---

/discipline:script-the-deterministic-work you tallied the numbers in notes/summary.md by eye earlier; recheck them
