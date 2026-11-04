---
description: "A repeat apply where nothing fails. setup SKILL.md lines 43-45 (apply runs check first; never prompt when the action is given), line 187 ('Re-running apply after everything passes changes nothing and reports already configured') and line 191 (does not run the formatter). The scaffold makes every row PASS or INFO on a host with node, jq and goimports: the clone declined the pre-commit entry, so verify prints declined. A host without those tools gets legitimate guidance from apply, so this case is host-bound. verify-ran is the with-only sign check ran (install.mjs ships only with the plugin). Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, apply, idempotent, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, formatter run, plugin CLI write, install.mjs plan/copy/decline/config-hook, Write or Edit; the reply reports already configured, repeats no install guidance for what resolves and asks the user nothing."
---

/go-format:setup apply

Everything passed on the last run. Go again.
