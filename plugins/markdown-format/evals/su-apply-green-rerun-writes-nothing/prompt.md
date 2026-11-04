---
description: "A repeat apply where nothing fails. setup SKILL.md lines 36-38 (apply runs check first; never prompt when the action is given), line 216 ('already configured'), lines 220-223 (the only execution is the --version probe). verify-ran and version-probe are the signs check ran; no-install is 'does not re-run a dependency install'; no-linter-run is 'lints, fixes and touches no repository content'. The scaffold opts in with a root config and declines the pre-commit entry, so verify prints declined rather than a FAIL. Host-bound: it needs node, jq and markdownlint-cli2, and without them apply gives legitimate guidance. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, apply, idempotent, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify and the markdownlint-cli2 --version probe run; no install, lint run, plugin CLI write, install.mjs plan/copy/decline/config-hook, config shell write, Write or Edit; the reply reports already configured."
---

/markdown-format:setup apply

Everything was green ten minutes ago. Run it again.
