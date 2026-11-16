---
description: "check with no python record and no Ruff config. setup SKILL.md check step 3: a none row is INFO unresolved, the opt-out by design; step 4 and Next route a record to /toolchain:setup apply python. The scaffold has no record or Ruff config, so the file_exists graders catch either written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, check, read-only, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record or config written, no Write or Edit. Both concerns unresolved INFO; not broken; opting in is a record via /toolchain:setup apply python or a Ruff config."
---

/python-format:setup check

Nothing gets formatted in this repo. Is python-format broken?
