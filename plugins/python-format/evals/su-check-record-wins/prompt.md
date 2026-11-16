---
description: "check in a repository that has both a ruff.toml and a committed python record (fix-cmd and lint-cmd run tools/fmt.sh and tools/lint.sh) matching the default branch. setup SKILL.md check step 3: each concern's row comes from format.sh and lint.sh --resolve; a record with approval accepted and its tool found is PASS, and the record is the first rung, ahead of the Ruff adapter. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, check, read-only, no-network, record]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No Write or Edit. The reply says format resolves to the repository's python record (tools/fmt.sh) and lint to the record's lint command (tools/lint.sh), both accepted because they match the default branch, and that the Ruff config does not decide either concern while the record does."
---

/python-format:setup check

We have a ruff.toml, but we also wrote our own format and lint scripts into the python record. Which ones will the hooks actually run?
