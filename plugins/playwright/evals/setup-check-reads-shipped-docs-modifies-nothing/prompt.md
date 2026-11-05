---
description: "Explicit check in a git repository whose .gitignore lacks .playwright-cli/. setup SKILL.md check: read the shipped skill and reference docs first, then report a PASS/FAIL/INFO table with a playwright-cli binary row, a browser-availability row (per reference/windows-quirks.md) and an artifact-directory row noting .playwright-cli/ is not gitignored; modify nothing. apply install-cli's global npm install is the one write path, and check must never take it. read-windows-quirks is a with-only indicator: the reference ships only with the plugin. No grader depends on whether playwright-cli or a browser is present on the host. The setup skill is disable-model-invocation and the prompt invokes it by slash command, so no Skill tool call is graded. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['setup', 'check', 'read-only']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
env: {EVAL_PLAYWRIGHT_SKIP_PYDEPS: "1"}
expected_outcome: 'Routes to check, reads the shipped reference docs, and reports a PASS/FAIL/INFO table with playwright-cli, browser and .playwright-cli/ rows, saying .playwright-cli/ is not gitignored; installs nothing, writes and edits nothing.'
---

/playwright:setup check
