---
description: "A repeat apply where nothing fails. setup SKILL.md lines 32-34 (apply runs check first; never prompt when the action is given), 142 and 189 ('Re-running apply after everything passes changes nothing and reports already configured') and 193-195 (never runs the formatter or linter). The legacy 'editing a .ps1 exercises the hook' half is dropped: the plugin has no per-edit hook, git commit exercises the entry (line 193), and the prompt does not raise it. The scaffold makes check PASS or INFO on a host with node, pwsh and PSScriptAnalyzer: a plain settings file with no CustomRulePath, and a clone that declined the pre-commit entry, so verify prints declined. A host without pwsh or the module gets legitimate guidance from apply, so this case is host-bound. verify-ran is the with-only sign check ran (install.mjs ships only with the plugin). Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [powershell-format, setup, apply, idempotent, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, analyzer or formatter run, plugin CLI write, install.mjs plan/copy/decline/config-hook, Write or Edit; the reply reports already configured, repeats no install guidance for what resolves and asks the user nothing."
---

/powershell-format:setup apply

Last run was clean. Run it once more.
