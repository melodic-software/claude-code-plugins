---
description: "Mutation audit on a repo with no mutation-testing config at any layer and a committed one-line change on a feature branch. audit SKILL.md Phase 0 and context/config-fallback.md: no config falls back to tool: manual and never refuses, but the test command is never guessed, so the run asks for it (or proposes one and waits for confirmation) before any baseline; no mutant runs, so no score or survivor is reported. A no-plugin model runs unittest and mutates by hand. Needs --scaffold --allow-tools Bash."
tags: [mutation-testing, audit, fallback, outcome, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply asks the user for the test command, or proposes one and asks them to confirm it, before running anything; it runs no tests, applies no mutant, and states no mutation score or survivor."
---

My test coverage on this branch is high but I do not trust it. Run mutation testing on this change and tell me whether the tests actually check it.
