---
description: "attended apply in a repository whose config shows black and flake8, with no record and no Ruff config. setup SKILL.md check step 4: draft fix-cmd and lint-cmd (each holding <files>; lint report-only) from the repository's own config and hand them to /toolchain:setup apply python, the one writer; this skill never writes the record. The file_exists grader catches a record written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, apply, no-network, record]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record written. The reply drafts fix-cmd (black over <files>) and a report-only lint-cmd (flake8 over <files>) and routes them to /toolchain:setup apply python."
---

/python-format:setup apply

I'm here. We format with black and lint with flake8; get python-format running them.
