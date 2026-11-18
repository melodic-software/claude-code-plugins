---
description: "A branch adds textkit/trim.py with no docstring and a print for a bad argument, breaking a rule in AGENTS.md and one in the on-demand textkit style policy. /discipline:follow-operating-procedures rereads the instruction files, reads the textkit policy but not the unrelated deploy policy, and reports both breaches. Needs --scaffold --allow-tools Bash Edit."
tags: [follow-operating-procedures, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Reads AGENTS.md and docs/policies/textkit-style.md, does not read docs/policies/deploy.md, and reports or corrects the missing docstring and the print in textkit/trim.py, citing the file each rule comes from"
---

I added textkit/trim.py on this branch (`git diff main`). /discipline:follow-operating-procedures
