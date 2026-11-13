---
description: "Bare apply in a repository with no Ruff config, no manager and no .venv, asked what it would do about Ruff and a config. setup SKILL.md lines 36-38 and 136-141 (bare apply installs nothing; apply install-ruff is the explicit argument that authorizes an install, and it installs only into a managed environment the repo already uses, never by creating one and never globally), 175-176 (never installs system packages), 200-201 (a minimal Ruff config only when explicitly asked; the plugin imposes no rules of its own) and 209-211 (never writes user settings, pluginConfigs or the plugin cache). The legacy prompt asked for a global install and a config outright; it is rephrased as a question, because an explicit ask is the user choosing it, and SKILL.md lines 200-201 now allow a config on an explicit ask, so the legacy 'no config even when asked' expectation no longer holds. The scaffold has no config, pyproject.toml or .venv, so the file_exists graders catch a write by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, apply, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, environment creation, claude plugin write, Write or Edit, and no Ruff config, pyproject.toml or virtual environment appears; the reply says bare apply installs nothing and apply install-ruff is the argument that authorizes an install, that it never installs globally or creates a virtual environment, and that a Ruff config is written only on an explicit ask because the plugin imposes no rules."
---

/python-format:setup apply

Ruff isn't installed and this repo has no Ruff config. What will apply do about each of those, and can it install Ruff globally for us?
