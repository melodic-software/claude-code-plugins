---
description: "Fault seeding on a repo with no mutation-testing config at any layer. seed-faults SKILL.md Phase 0 resolves the config as audit does, and the test command is never guessed: the run asks for it, or proposes one and waits, before any baseline, worktree seed or test run. A no-plugin model guesses `python3 -m unittest`, plants bugs and reports a count. Needs --scaffold --allow-tools Bash Edit."
tags: [mutation-testing, seed-faults, fallback, outcome, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Edit]
expected_outcome: "The reply asks the user for the test command, or proposes one and asks them to confirm it; no test runs and no seed is applied."
---

Seed a few faults into this code and see whether my tests catch them.
