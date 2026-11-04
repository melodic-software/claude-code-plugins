---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet (lines 157-183): claude plugin configure --values-stdin with every value a string is preferred; the claude plugin install --config rerun is the fallback for a release without plugin configure, and against an installed plugin it prints already installed and still writes the value; never uninstall (it resets every option); configure has no scope flag and runs from the project the plugin is installed in; -s defaults to user, so pass the scope claude plugin list reports, and user from the home directory; a same-session check still reports the old value, so rerun check in a fresh session. Step 6 (lines 81-83): any value other than true disables the hooks. The prompt raises each claim. No grader requires the reply to cite the plugin-reconfiguration convention: the skill cites it as its own source and never tells the reply to name it, so that legacy expectation is dropped. Legacy 'ends by rerunning check' is now the fresh-session rerun of lines 180-183. no-plugin-cli-write guards a claude plugin write the run makes itself (line 180). Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [powershell-format, setup, apply, reconfigure, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Routes the headless change to claude plugin configure powershell-format@<marketplace> --values-stdin with {\"powershell_format_enabled\": \"false\"}, then the claude plugin install --config powershell_format_enabled=false rerun as the fallback that still writes on an installed plugin; rules out uninstalling; gives the scope rule; says any value other than true disables the hooks; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself."
---

/powershell-format:setup apply

I'm on a CI box with no interactive session. How do I turn the powershell-format hook off? What if this Claude Code release has no plugin configure, and does the rerun do anything when the plugin is already installed? Could I just uninstall and reinstall instead? Which scope do I use and where do I run it, which values count as off, and how do I tell it worked?
