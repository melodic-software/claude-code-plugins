---
description: "check, asked why an edit to a gitignored file was left alone. setup SKILL.md step 5 (the effective javascript_format_enabled and javascript_format_lint_gitignored values; unexpanded or empty means the default, true and false), with apply's toggle bullet for the native configure flow and the headless routes cited from the plugin-reconfiguration convention, and 'this skill never writes user settings or pluginConfigs'. hooks/javascript-format.sh line 98 skips a gitignored file unless the option is true; README line 137 names the option. The scaffold has .work/ in .gitignore and an unformatted, untracked .work/scratch.ts. The prompt raises the values, the empty reading and biome.json, which the legacy prompt did not. Legacy 'modifies no setting' is enforced by the must-not graders. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [javascript-format, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, biome check or format run, claude plugin write, install.mjs write verb, config write, Write or Edit; the reply reports javascript_format_enabled and javascript_format_lint_gitignored with their effective values, reads an empty or unexpanded value as the default, says the untouched gitignored file is not a defect, names setting javascript_format_lint_gitignored to true through the native flow, and says biome.json is not the place."
---

/javascript-format:setup check

I edited .work/scratch.ts and the hook left it alone. Is that a defect? What values do javascript_format_enabled and javascript_format_lint_gitignored have right now, and what does an empty or unexpanded value mean? How would I get such files rewritten: do I change biome.json, or something else?
