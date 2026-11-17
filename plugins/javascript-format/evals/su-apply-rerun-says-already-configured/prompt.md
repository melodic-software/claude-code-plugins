---
description: "A repeat apply where nothing fails. setup SKILL.md action routing (apply runs check first; never prompt when the action is given), 'Re-running apply after everything passes changes nothing and reports already configured' and 'What this skill does not do' (does not run the formatter or the linter). The scaffold makes every row PASS or INFO on a host with node and jq: a root biome.json, a gitignored root node_modules/.bin/biome stub, and a clone that declined both pre-commit entries, so verify prints declined. A host without node or jq gets legitimate guidance from apply, so this case is host-bound. verify-ran is the with-only sign check ran (install.mjs ships only with the plugin). Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [javascript-format, setup, apply, idempotent, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, biome check or format run, claude plugin write, install.mjs plan/copy/decline/config-hook, Write or Edit; the reply reports already configured, repeats no install guidance for what resolves and asks the user nothing."
---

/javascript-format:setup apply

Everything passed on the previous run. Go again.
