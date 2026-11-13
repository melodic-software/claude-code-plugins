---
description: "check in a scaffolded repository where the hook's walks give different answers per file. setup SKILL.md check: 'Read it first' (lines 46-48: read hooks/python-format.sh and probe what it does), step 3 (lines 59-64: resolve Ruff through the hook's repo .venv walk, then PATH; the scaffold's gitignored .venv/bin/ruff stub is what the hook resolves), step 4 (lines 65-72: the walk stops at the closest governing config; a pyproject.toml counts only with a [tool.ruff] section or [tool.ruff.*] subtable, so src/ruff.toml governs src/pkg/mod.py past src/pkg/pyproject.toml, and the root pyproject.toml's [tool.ruff.lint] subtable governs scripts/run.py), step 8 (line 87: run install.mjs verify) and the PASS/FAIL/INFO table with nothing modified. The prompt asks which config and binary apply because the walk is per edited file. reads-hook-script and verify-ran are with-only: both files ship only with the plugin. The legacy jq and Node.js absence expectations cannot be staged on a host that has both; su-check-missing-jq-node-graded covers them. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, check, read-only, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The hook script is read and install.mjs verify runs; no install, environment change, install.mjs plan/copy/decline/config-hook, ruff check or format run, Write or Edit; the reply is a PASS/FAIL/INFO table with jq, Ruff, Node.js, config, toggle and pre-commit rows, resolves Ruff at .venv/bin/ruff, names src/ruff.toml for src/pkg/mod.py (src/pkg/pyproject.toml does not count) and the root pyproject.toml for scripts/run.py (its [tool.ruff.lint] subtable counts)."
---

/python-format:setup check

Which Ruff config would the hook use for src/pkg/mod.py, which for scripts/run.py, and which ruff binary would it run?
