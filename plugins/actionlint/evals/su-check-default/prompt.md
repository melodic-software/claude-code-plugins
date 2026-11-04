---
description: "Bare /actionlint:setup runs the read-only check. setup SKILL.md lines 39 ('no argument or `check` runs the check'), 50-51 ('report a PASS/FAIL/INFO table ... Do not modify anything'), 71-72 (report the effective actionlint_enabled value), 79 (run install.mjs verify), 194-198 (no linter run, no install, nothing executed beyond command -v and verify). status-table and toggle-reported are the result graders; verify-ran is a with-only indicator, since install.mjs exists only with the plugin. No grader requires a Bash command -v: lines 18-19 tell the model to read the rendered rows instead. reads-hook-script (with-only) checks lines 46-49 ('Read it first'): the git-hook script ships only with the plugin, and a model that reads it through cat instead of Read fails it. covers-check-steps needs a verdict row for steps 1 and 4-7 (Bash, config, toggle, registration, pre-commit entry) beside status-table's node and actionlint rows; a row label is matched in any cell of its row. Needs --allow-tools Bash Write Edit so the must-not calls can fail."
tags: [actionlint, setup, outcome, read-only]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read, Write, Edit]
expected_outcome: "No package install, install.mjs plan/copy/decline/config-hook, actionlint lint run, Write or Edit; the git-hook script is read; the reply is a PASS/FAIL/INFO table with a row for every check step (Bash, node, actionlint, config, toggle, registration, pre-commit entry) and reports the actionlint_enabled value."
---
/actionlint:setup
