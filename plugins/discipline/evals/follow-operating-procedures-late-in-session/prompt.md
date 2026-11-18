---
description: "A resumed session added textkit/trim.py several turns ago, breaking two rules. Invoked late, /discipline:follow-operating-procedures rereads the rules and finds the earlier work's drift. Runs one arm, since the case resumes a history. Needs --scaffold --allow-tools Bash Edit."
tags: [follow-operating-procedures, scaffold, history]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Reads AGENTS.md and the textkit policy and reports the missing docstring and the print in the trim helper added earlier in the session"
---

/discipline:follow-operating-procedures
