---
description: "Routine. Phase 3 predicts which allow rules auto mode sets aside on entry: Bash(python3 *) (interpreter-wildcard) and Bash(npx *) (package-manager-run) drop, narrow rules carry over. The skill must state the precondition (only a session that enters auto mode makes the transition) and that dropped rules are restored when the session leaves auto mode, nothing edited. Source: the before SKILL.md Phase 3. Needs --scaffold --allow-tools Bash Write Edit."
tags: [routine, audit-permission-state, outcome, entry-diff, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The entry diff runs; the reply names Bash(python3 *) and Bash(npx *) as dropped while auto mode is active and Bash(pytest) and Bash(ruff check .) as kept, states that this applies only to sessions that enter auto mode, and writes nothing."
---

/harness-config:audit-permission-state --entry-diff

Which of these allow rules will still work once a session is in auto mode?
