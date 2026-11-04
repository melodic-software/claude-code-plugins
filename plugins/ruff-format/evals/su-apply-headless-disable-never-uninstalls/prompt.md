---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet (lines 177-199): claude plugin configure --values-stdin with every value a string is preferred (2.1.285 or later); the claude plugin install --config rerun is the fallback, and against an installed plugin it prints already installed and still writes the value; never uninstall (it resets every option); configure has no scope flag and either route runs from the project the plugin is installed in; -s defaults to user, so pass the scope claude plugin list reports, and user from the home directory; a same-session check still reports the old value, so rerun check in a fresh session. No grader requires the reply to cite the plugin-reconfiguration convention: the skill cites it as its own source and never tells the reply to name it. The skill never writes user settings or pluginConfigs, so no-plugin-cli-write guards a claude plugin write the run makes itself. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [ruff-format, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Routes the headless change to claude plugin configure ruff-format@<marketplace> --values-stdin with {"ruff_format_enabled": "false"}, then the claude plugin install --config ruff_format_enabled=false rerun as the fallback that still writes on an installed plugin; rules out uninstalling; gives the scope rule; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself.'
---

/ruff-format:setup apply

I'm on a CI box with no interactive session. How do I turn the ruff-format hook off?
