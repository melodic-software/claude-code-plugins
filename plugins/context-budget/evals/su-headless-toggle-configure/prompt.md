---
description: 'Headless toggle change routes to claude plugin configure, never an uninstall. setup is user-invoked only, so the case starts with its slash command and carries no Skill grader. setup SKILL.md lines 107-130: per the plugin-reconfiguration convention (which owns the verified-version record), headless preferred is claude plugin configure context-budget@<marketplace> --values-stdin with {"settings_write_ask_enabled": "false"} (every value a string; 2.1.285 or later); fallback is the claude plugin install ... -s <scope> --config settings_write_ask_enabled=false rerun, which on an installed plugin prints already installed and still writes the value; never uninstall, which drops the whole pluginConfigs entry and resets every option in the README Options reference; pass the scope claude plugin list reports (user from the home directory), -s places enabledPlugins, and the value lands in user settings; rerun check in a fresh session and report the observed value. Line 115: print the commands, never run either. no-restated-versions fails a Claude Code version other than 2.1.285 stated as verified, measured, tested or confirmed; it is confined to those words because check may report the host''s probed version (line 69). Needs --allow-tools Bash.'
tags: [context-budget, setup, outcome, reconfigure, must-not, no-network]
runs: 3
max_turns: 15
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: 'Routes the change to claude plugin configure context-budget@<marketplace> --values-stdin with {"settings_write_ask_enabled": "false"}, then the claude plugin install --config rerun as the fallback that still writes on an installed plugin; rules out uninstalling and says why; cites the plugin-reconfiguration convention; gives the scope rule; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself.'
---

/context-budget:setup I want settings_write_ask_enabled set to false, headless. I cannot use the interactive configure prompt from this session.
