---
description: "check in a repository whose only pyproject.toml has no [tool.ruff] section and no python record. setup SKILL.md check step 3 (the --resolve rows read none for both concerns, INFO unresolved, the opt-out by design, so the plugin is inert, not broken; the detail says the pyproject.toml has no [tool.ruff] section; a missing adapter tool is not FAIL while nothing resolves to it) and apply's last bullet (the plugin imposes no rules and no tool; a minimal config is offered only when explicitly asked). The scaffold has no ruff.toml or .ruff.toml, so the file_exists graders catch a config write by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, check, read-only, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No Ruff config is written and none is offered; no install, Write or Edit; the reply says the plugin is not broken: no config governs the repo, which is INFO, the opt-out by design; the pyproject.toml without a [tool.ruff] section does not count; and the Ruff binary is not a FAIL while no config governs."
---

/python-format:setup check

There's no Ruff config anywhere in this repo and Python files are never formatted. Is the plugin broken?
