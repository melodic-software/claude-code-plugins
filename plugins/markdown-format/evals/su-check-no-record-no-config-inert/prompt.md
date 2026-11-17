---
description: "check with no markdown record and no markdownlint config. setup SKILL.md check steps 5 and 6: a none row is INFO unresolved, the opt-out by design; the hooks run only the markdownlint-cli2 adapter, and a markdown record runs only through /toolchain:lint and /toolchain:check, written by /toolchain:setup apply markdown. The file_exists graders catch a record or markdownlint config written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, check, read-only, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record or config written, no Write or Edit. Both concerns unresolved INFO; not broken; the way forward is a markdownlint config for the hooks, or a markdown record for /toolchain:lint."
---

/markdown-format:setup check

Nothing gets formatted or linted in this repo. Is markdown-format broken?
