---
description: "apply asked how to turn the hook off headless. setup SKILL.md apply's toggle bullet: claude plugin configure --values-stdin preferred (2.1.285 or later), the claude plugin install --config rerun as fallback, never uninstall (it resets every option), -s defaults to user, and a same-session check still reports the old value, so rerun check in a fresh session. No grader requires the reply to cite the plugin-reconfiguration convention: the skill cites it as its own source and never tells the reply to name it. The skill never writes user settings or pluginConfigs, so no-plugin-cli-write guards a claude plugin write the run makes itself. Needs --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'apply', 'reconfigure', 'must-not']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Routes the headless change to claude plugin configure eol-normalizer@<marketplace> --values-stdin with {"eol_normalizer_enabled": "false"}, then the claude plugin install --config eol_normalizer_enabled=false rerun as the fallback; rules out uninstalling; says -s defaults to user; tells the user to rerun check in a fresh session and report the observed value; runs no claude plugin write itself.'
---

/eol-normalizer:setup apply

I'm on a CI box with no interactive session — how do I turn the hook off?
