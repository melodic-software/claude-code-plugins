---
description: "Phase 1 runs the report and captures the ZeroDivisionError before any edit to report.py"
tags: [debug, phase1-red-run]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Runs report.py on data/week.json (or a test over it) and sees the ZeroDivisionError before editing report.py, and the reply names the observed error"
---

/debugging:debug the weekly hours report crashes on some weeks. This week's data is in data/week.json and the script is report.py. Find and fix it.
