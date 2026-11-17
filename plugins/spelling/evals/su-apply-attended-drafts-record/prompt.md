---
description: "attended apply in a repository whose config shows cspell, with no spelling record and no typos config. setup SKILL.md check step 4: the hooks run only the shipped typos adapter and never a record, so the skill says so, drafts lint-cmd (holding <files>, report-only) from the repository's own config, and hands it to /toolchain:setup apply spelling, the one writer, for /toolchain:lint and /toolchain:check to run; it never writes the record. The file_exists grader catches a record written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, apply, no-network, record]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record written. The reply says the hooks will not run cspell, drafts a report-only lint-cmd (cspell over <files>) and routes it to /toolchain:setup apply spelling, for /toolchain:lint to run."
---

/spelling:setup apply

I'm here. We spell-check with cspell; get the spelling plugin running it.
