---
description: "Hard. Already enforced gate: a higher rung covers the concern (pre-commit runs ruff and ruff-format, CI runs ruff format --check and ruff check), and the shift-left carve-out never places a report-only duplicate in a per-edit PostToolUse hook; PostToolUse 'cannot block a tool call'. Hard because the user proposes the hook and phrases it as a gate. At risk in the sandbox: the skill persists verdicts under ${CLAUDE_PLUGIN_DATA} (Persist the findings), which the sandbox denied on slice A; every grader reads the report or the tool calls before that write. Needs network for the Phase 2.2 docs batch. Needs --scaffold --allow-tools Bash Write Edit WebFetch Agent."
tags: [hard, audit-automation-gaps, outcome, already-enforced, scaffold, plugin-data-risk]
runs: 3
max_turns: 30
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit, WebFetch, Agent]
expected_outcome: "The reply rejects the per-edit PostToolUse ruff hook because pre-commit and CI already run ruff, does not claim PostToolUse can block the edit, and writes no hook or settings file."
---

/harness-config:audit-automation-gaps hooks

Are we missing any hooks? I was going to add a PostToolUse hook that runs ruff format and ruff check after every edit so Claude can't save badly formatted code.
