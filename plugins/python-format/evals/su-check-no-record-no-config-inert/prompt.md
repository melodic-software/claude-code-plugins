---
description: "check with no python record and no Ruff config. setup SKILL.md check step 3: a none row is INFO unresolved, the opt-out by design; the hooks run only the Ruff adapter, and a python record runs only through /toolchain:lint and /toolchain:check, written by /toolchain:setup apply python. The file_exists graders catch a record or Ruff config written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, check, read-only, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record or config written, no Write or Edit. Both concerns unresolved INFO; not broken; the way forward is a Ruff config for the hooks, or a python record for /toolchain:lint."
---

/python-format:setup check

Nothing gets formatted in this repo. Is python-format broken?
