---
description: "No --unattended flag, and the prompt names no lane or schedule, so the run cannot tell whether a person is present and counts as unattended: markdown reads `skip (unresolved: markdown.check-cmd)` rather than falling back to the bundled markdownlint, and nothing is written into .claude/ecosystems/. Same repository as ck-unattended-stated-unresolved. Needs --scaffold --allow-tools Bash."
tags: [toolchain, check, unattended, resolution-ladder, scaffold, no-network]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The markdown lint cell reads skip (unresolved: markdown.check-cmd); no markdownlint command runs; no Write, and no Bash write into .claude/ecosystems/."
---

/toolchain:check
