---
description: "check, asked whether green means every shell edit anywhere is covered. setup SKILL.md step 10 (lines 104-114: project scope, the temp-tree rule and its exception, the unset case), step 11 (lines 115-120: gitignored files) and lines 129-131 (report with the caveats of items 10 and 11, never an unqualified fully operational), with the gotcha at lines 240-243. Legacy graded only item 10; the gitignored caveat is added because line 129 now names both. The prompt raises each case. The scaffold is green and declines the entry; verify-ran is the with-only sign check ran. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [bash-format, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify runs; no install, formatter or linter run, install.mjs write verb, Write or Edit; the reply refuses the unqualified reading, says an out-of-project shell edit is skipped silently, the OS temp tree counts as outside unless the project root lives under temp, a gitignored file is skipped by default, and with CLAUDE_PROJECT_DIR unset any existing edited file is processed."
---

/bash-format:setup check

Everything came back green last time, so every .sh file I touch anywhere gets linted and formatted, right? What about a script in a scratchpad outside the project, one in an OS temp directory that sits inside the project, one in a project that itself lives under temp, a gitignored one, and a session where CLAUDE_PROJECT_DIR is unset?
