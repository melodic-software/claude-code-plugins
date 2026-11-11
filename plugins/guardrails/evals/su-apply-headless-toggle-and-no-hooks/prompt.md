---
description: 'Legacy apply-points-only-never-writes, with legacy install-git-hooks-is-explicit-only merged in (same /guardrails:setup apply prompt). SKILL.md apply: reconfigure through the native configure flow, through the headless claude plugin configure route (configure-route accepts only that route, since the prompt rules out the interactive one), with the routes and caveats read from the plugin-local copy of the plugin-reconfiguration convention; never uninstall to reconfigure; rerun check in a fresh session. The routes, the fallback, its rerun behavior, the scope rule and the failure signals now live in the plugin-local copy of the plugin-reconfiguration contract the skill links, and fallback-after-configure, scope-rule and failure-signals grade them there. install-git-hooks never runs from bare apply. verify-ran shows check ran first. ''never installs system packages'' is no-install. Host tools: jq 1.6+, shfmt 3.14.1+, node, bash 5+ and git; without jq or shfmt the with-plugin arm''s own guards deny every Bash call. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail.'
tags: [guardrails, setup, apply, reconfigure, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs check, then routes to the native configure flow for guardrails@<marketplace> with block_cd_prefix_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the scope and the failure signals; rules out uninstalling; gives the fresh-session rerun; says bare apply installs no git hook and apply install-git-hooks does; installs, writes and runs no plugin CLI write itself.'
---

/guardrails:setup apply

I'm on a CI box with no interactive session and want block-cd-prefix off. What exactly do I run? What if this Claude Code release has no plugin configure? Could I just uninstall and reinstall? Which scope do I pass, and where do I run it? How does each route tell me a value was rejected, and how do I confirm the change took? Does this bare apply install the guardrails git hooks, and if not, what does?
