---
description: "check in a repository whose only pyproject.toml has no [tool.ruff] section. setup SKILL.md check step 4 (lines 65-72: a pyproject.toml counts only with a [tool.ruff] section or [tool.ruff.*] subtable; no governing config is INFO, the opt-out by design, so the plugin is inert, not broken), step 3 (lines 63-64: a missing Ruff binary is FAIL only while a Ruff config governs the repo) and apply's last bullet (lines 200-201: a minimal Ruff config is offered only when explicitly asked; the plugin imposes no rules of its own). The scaffold has no ruff.toml or .ruff.toml, so the file_exists graders catch a config write by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, check, read-only, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No Ruff config is written and none is offered; no install, Write or Edit; the reply says the plugin is not broken: no config governs the repo, which is INFO, the opt-out by design; the pyproject.toml without a [tool.ruff] section does not count; and the Ruff binary is not a FAIL while no config governs."
---

/python-format:setup check

There's no Ruff config anywhere in this repo and Python files are never formatted. Is the plugin broken?
