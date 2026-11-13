---
description: "A repeat apply where nothing fails. setup SKILL.md lines 36-38 (apply runs check first; never prompt when the action is given), 136 (run check, then offer a resolution per FAIL) and 203 ('Re-running apply after everything passes changes nothing and reports already configured'). The scaffold makes every check step PASS or INFO on a host with jq and node: a [tool.ruff] section governs, ruff is a recorded uv dev dependency, the hook resolves the gitignored .venv/bin/ruff stub, and the clone has declined the pre-commit entry, so install.mjs verify prints declined (INFO). verify-ran is the with-only sign that check ran (install.mjs ships only with the plugin); already-configured is the result grader; no-env-change catches a re-add or sync through uv. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, apply, idempotent, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, uv add/sync/lock or other environment change, install.mjs plan/copy/decline/config-hook, Write or Edit; the reply reports already configured and asks the user nothing."
---

/python-format:setup apply

Everything passed on the last run. Go again.
