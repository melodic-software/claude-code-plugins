---
description: "check, asked why an edit to a gitignored script was not formatted. setup SKILL.md step 8 (effective bash_format_enabled and bash_format_lint_gitignored values; unexpanded or empty means the manifest default) and step 11 (a gitignored file is silently skipped, INFO; a tracked file matching an ignore pattern stays in scope; when git cannot decide the hook acts as before), with apply's toggle bullet for the native configure flow, the headless routes cited from the plugin-reconfiguration convention, and the fresh-session rule. The prompt raises the opt-in, the tracked file and the undecidable case. The scaffold has a section naming shell files, so the opt-in is not the reason, and an untracked .work/scratch.sh that .gitignore covers; it declines the entry. verify-ran is the with-only sign check ran. .gitignore already exists, so no-config-shell-write, no-write and no-edit guard it. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [bash-format, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, formatter or linter run, plugin CLI write, install.mjs write verb, config write, Write or Edit; the reply reports both effective option values, says the gitignored file is silently skipped, INFO not a defect, names setting bash_format_lint_gitignored to true through the native configure flow, confirmed in a fresh session, and says a tracked file stays in scope and an undecidable git leaves the file processed."
---

/bash-format:setup check

I edited .work/scratch.sh and nothing was formatted. .work/ is in our .gitignore. Is bash-format broken? What are the option values in effect, and how would I opt in, including from a headless session, and when does that take effect? What if the file were tracked even though it matches the ignore pattern, or if git couldn't decide?
