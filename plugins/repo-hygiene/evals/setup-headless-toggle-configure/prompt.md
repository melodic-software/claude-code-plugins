---
description: 'Headless toggle change routes to the native configure flow, never an uninstall. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md "Toggle off (or on)": set clean_destructive_guard_enabled through the native configure flow, with the headless routes and their scope and failure-signal caveats cited from the plugin-reconfiguration convention rather than restated (cites-reconfiguration-convention); never uninstall to reconfigure; rerun check in a fresh session and report the observed value. The routes, the fallback, its rerun behavior, the scope rule and the failure signals now live in the plugin-reconfiguration contract the skill points at, and fallback-after-configure, already-installed-still-writes and scope-rule grade them there; a with-plugin run that cannot reach the contract fails them. setup never writes user settings or pluginConfigs, so no-plugin-command-run fails a claude plugin write the run makes itself. no-restated-versions fails any Claude Code version other than 2.1.285 (the convention owns the measured releases). Bash is in allowed_tools for the SKILL.md pre-computed ghq line and so no-plugin-command-run can fail. Needs --allow-tools Bash.'
tags: [repo-hygiene, setup, outcome, reconfigure, must-not, no-network]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'Routes the change to the native configure flow for repo-hygiene@<marketplace> with clean_destructive_guard_enabled set to true, pointing at the plugin-reconfiguration convention for the headless routes, the scope and the failure signals; rules out uninstalling; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself.'
---

/repo-hygiene:setup Turn clean_destructive_guard_enabled back on headlessly. I cannot use the interactive configure prompt from this session.
