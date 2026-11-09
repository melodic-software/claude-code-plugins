---
description: 'Legacy apply-points-only-never-writes, with legacy install-git-hooks-is-explicit-only merged in (same /guardrails:setup apply prompt). SKILL.md apply (lines 106-137): configure --values-stdin with every value a string is preferred (lines 117-121); the install --config rerun is the fallback and still writes on an installed plugin (lines 121-124); never uninstall, which resets every option (lines 124-126); configure has no scope flag, so run it from the project, and the rerun takes the scope claude plugin list reports (lines 127-131); --values-stdin exits 1 on a bad value while --config exits 0, so read its output (lines 131-134); rerun check in a fresh session (lines 135-137). install-git-hooks never runs from bare apply (line 162). verify-ran shows check ran first (line 108). Dropped: ''cites the plugin-reconfiguration convention as the owner of the verified-version record'' (the skill cites it as its own source and never tells the reply to name it), and ''never installs system packages'' is no-install. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, apply, reconfigure, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs check, then routes to claude plugin configure guardrails@<marketplace> --values-stdin with {"block_cd_prefix_enabled": "false"}, then the install --config rerun; rules out uninstalling with its reason; gives the scope rule, both failure signals and the fresh-session rerun; says bare apply installs no git hook and apply install-git-hooks does; installs, writes and runs no plugin CLI write itself.'
---

/guardrails:setup apply

I'm on a CI box with no interactive session and want block-cd-prefix off. What exactly do I run? What if this Claude Code release has no plugin configure? Could I just uninstall and reinstall? Which scope do I pass, and where do I run it? How does each route tell me a value was rejected, and how do I confirm the change took? Does this bare apply install the guardrails git hooks, and if not, what does?
