---
description: "Bare /actionlint:setup runs the read-only check. setup SKILL.md lines 39 ('no argument or `check` runs the check'), 50-51 ('report a PASS/FAIL/INFO table ... Do not modify anything'), 71-72 (report the effective actionlint_enabled value), 79 (run install.mjs verify), 187-191 (no linter run, no install, nothing executed beyond command -v and verify). status-table and toggle-reported are the result graders; verify-ran is a with-only indicator, since install.mjs exists only with the plugin. No grader requires a Bash command -v: lines 18-19 tell the model to read the rendered rows instead. Needs --allow-tools Bash Write Edit so the must-not calls can fail."
tags: [actionlint, setup, outcome, read-only]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Bash, Read, Write, Edit]
expected_outcome: "No package install, install.mjs plan/copy/decline/config-hook, actionlint lint run, Write or Edit; the reply is a PASS/FAIL/INFO table with actionlint and node rows and reports the actionlint_enabled value."
---
/actionlint:setup
