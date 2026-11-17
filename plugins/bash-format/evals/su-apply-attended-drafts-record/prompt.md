---
description: "attended apply in a repository whose Makefile shows beautysh and bashate, with no record and no adapter config. setup SKILL.md check step 5: the hooks run only the shipped shfmt and ShellCheck adapters and never a record, so the skill says so, drafts fix-cmd and lint-cmd (each holding <files>; lint report-only) from the repository's own config, and hands them to /toolchain:setup apply bash, the one writer, for /toolchain:lint and /toolchain:check to run; it never writes the record. The file_exists grader catches a record written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [bash-format, setup, apply, no-network, record]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record written. The reply says the hooks will not run beautysh or bashate, drafts fix-cmd (beautysh over <files>) and a report-only lint-cmd (bashate over <files>) and routes them to /toolchain:setup apply bash, for /toolchain:lint to run."
---

/bash-format:setup apply

I'm here. We format with beautysh and lint with bashate; get bash-format running them.
