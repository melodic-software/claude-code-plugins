---
description: 'A refresh on a detached HEAD off the default branch tip commits nothing. refresh.md Before the pass step 3 names that start report only; Commit has it commit nothing and leave each check that had a write blocked, its edits in the report.'
tags: [formal-verification, specify, refresh, branch, unattended, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep]
expected_outcome: 'Opens with "Check one-holder (formal-lock): blocked" naming the detached HEAD off the tip, keeps the model update in the report unwritten, and commits, pushes, branches and opens nothing.'
---

/formal-verification:specify refresh --unattended. Describe what the pass would do; take no actions: do not read the repository, run anything, write or commit, and treat these as facts. The pass runs in CI on a detached HEAD at e4e4e4e, a pull request's test merge commit; the tip of main is d3d3d3d, a different commit. The repository has one formal-area skill, .claude/skills/formal-lock/, with one check, `one-holder`, covering src/lock.js, sync commit a1b2c3d. Since then a commit split take() into check() and set(), so the model's one step is now two in the code. The model checker is installed. After the model is updated to two steps the check passes, and a seeded break that swaps the two steps is caught. Name the outcome, what is written and committed, and whether it pushes, creates a branch or opens a pull request, then stop.
