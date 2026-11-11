---
description: 'Headless toggle change routes to the native configure flow, never an uninstall. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md remediation''s toggle bullet: set settings_write_ask_enabled through the native configure flow, with the headless routes and their scope and failure-signal caveats cited from the plugin-reconfiguration convention (which owns the verified-version record) rather than restated (cites-reconfiguration-convention); print the route, never run one; never uninstall to reconfigure; rerun check in a fresh session and report the observed value. The routes'' flags, version floor, fallback, scope rule and failure signals are graded nowhere, since the skill no longer states them. no-restated-versions fails a Claude Code version other than 2.1.285 stated as verified, measured, tested or confirmed; it is confined to those words because check may report the host''s probed version. Needs --allow-tools Bash.'
tags: [context-budget, setup, outcome, reconfigure, must-not, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'Routes the change to the native configure flow for context-budget@<marketplace> with settings_write_ask_enabled set to false, pointing at the plugin-reconfiguration convention for the headless routes, the scope and the failure signals; rules out uninstalling; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself.'
---

/context-budget:setup I want settings_write_ask_enabled set to false, headless. I cannot use the interactive configure prompt from this session.
