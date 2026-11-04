---
description: "apply asked how to turn the hooks back on headless. setup SKILL.md apply's toggle bullet (lines 139-164): claude plugin configure --values-stdin with every value a string is preferred (2.1.285 or later); the claude plugin install --config rerun is the fallback, and against an installed plugin it prints already installed and still writes the value; never uninstall (it resets every option); -s defaults to user, so pass the scope claude plugin list reports and run from the project for a project or local scope; a same-session check still reports the old value, so rerun check in a fresh session. No grader requires the reply to cite the plugin-reconfiguration convention: the skill cites it as its own source and never tells the reply to name it. The skill never writes user settings or pluginConfigs, so no-plugin-cli-write guards a claude plugin write the run makes itself. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [actionlint, setup, apply, reconfigure, must-not]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Routes the headless change to claude plugin configure actionlint@<marketplace> --values-stdin with {"actionlint_enabled": "true"}, then the claude plugin install --config actionlint_enabled=true rerun as the fallback that still writes on an installed plugin; rules out uninstalling; gives the scope rule; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself.'
---

/actionlint:setup apply

I'm on a CI box with no interactive session. How do I turn the actionlint hooks back on?
