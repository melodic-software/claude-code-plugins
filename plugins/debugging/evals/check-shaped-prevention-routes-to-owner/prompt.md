---
description: "Phase 6 Prevention with a check-shaped answer and both owner plugins said to be installed: the post-mortem says a deterministic check would have caught the banned datetime.utcnow() call, routes it to /corrections:codify (a repo mistake, not /session-flow:retro) with that call as the mistake, and proposes the check without writing a lint config, hook or analyzer rule. Scaffold: a git repository whose AGENTS.md bans utcnow, with the fix and regression test committed and a pyproject.toml ruff section. Write, Edit and Bash are granted so the forbidden writes are reachable; a write under .claude/ is sandbox-denied and would read INVALID. Needs --scaffold --allow-tools Bash Edit Write"
tags: [debug, converted, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "The post-mortem states that a deterministic check (a lint or analyzer rule, a test or a hook) would have caught the banned datetime.utcnow() call, names /corrections:codify as its owner rather than /session-flow:retro because the mistake is in the repository's code, gives that skill the utcnow call as the mistake to describe, and writes or edits no lint config, hook or analyzer rule"
---

/debugging:debug is done: the report export crashed because a handler called the deprecated datetime.utcnow() the repo bans, and the fix and regression test are in. Write the post-mortem. Both the corrections and session-flow plugins are installed.
