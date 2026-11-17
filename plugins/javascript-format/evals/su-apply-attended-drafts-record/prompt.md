---
description: "attended apply in a repository whose config shows Prettier and ESLint, with no record and no Biome config. setup SKILL.md check step 4: the hooks run only the shipped Biome adapter and never a record, so the skill says so, drafts fix-cmd and lint-cmd (each holding <files>; lint report-only) from the repository's own config, and hands them to /toolchain:setup apply <id>, the one writer, for /toolchain:lint and /toolchain:check to run; it never writes the record. The file_exists grader catches a record written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [javascript-format, setup, apply, no-network, record]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record written. The reply says the hooks will not run Prettier or ESLint, drafts fix-cmd (Prettier writing <files>) and a report-only lint-cmd (ESLint over <files>) and routes them to /toolchain:setup apply, for /toolchain:lint to run."
---

/javascript-format:setup apply

I'm here. We format with Prettier and lint with ESLint; get javascript-format running them.
