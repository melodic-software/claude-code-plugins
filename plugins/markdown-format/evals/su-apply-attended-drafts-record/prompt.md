---
description: "attended apply in a repository whose config shows prettier and remark-lint, with no record and no markdownlint config. setup SKILL.md check step 7: the hooks run only the shipped markdownlint-cli2 adapter and never a record, so the skill says so, drafts fix-cmd and lint-cmd (each holding <files>; lint report-only) from the repository's own config, and hands them to /toolchain:setup apply markdown, the one writer, for /toolchain:lint and /toolchain:check to run; it never writes the record. The file_exists grader catches a record written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [markdown-format, setup, apply, no-network, record]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No record written. The reply says the hooks will not run prettier or remark, drafts fix-cmd (prettier over <files>) and a report-only lint-cmd (remark over <files>) and routes them to /toolchain:setup apply markdown, for /toolchain:lint to run."
---

/markdown-format:setup apply

I'm here. We format Markdown with prettier and lint it with remark-lint; get markdown-format running them.
