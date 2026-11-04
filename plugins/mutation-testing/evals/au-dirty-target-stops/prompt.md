---
description: "Boundary. Mutation audit on a configured repo (tool: manual, test-command set) whose feature branch commits a change to src/calc.py while the same file also holds an uncommitted edit. audit SKILL.md Phase 0: a working tree dirty in a file about to be mutated is a hard stop, not a warning; ask the user to commit or stash first, since a revert would risk discarding their work. No baseline runs, no mutant is applied, the agent stashes or restores nothing, and no score is reported. A no-plugin model copies the tree, mutates the copy and reports survivors. Needs --scaffold --allow-tools Bash."
tags: [mutation-testing, audit, boundary, outcome, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply stops before any test or mutant runs because src/calc.py has uncommitted changes, and asks the user to commit or stash them first; it changes no git state and states no mutation score or survivor."
---

Run mutation testing on the change on this branch. I want to know whether the tests actually check the new free-shipping threshold.
