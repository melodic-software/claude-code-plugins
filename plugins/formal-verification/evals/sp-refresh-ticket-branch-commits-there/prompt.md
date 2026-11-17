---
description: 'A refresh started on a ticket branch commits there. refresh.md Before the pass steps 3 and 4: a ticket branch whose own diff touches no covered path is checked at its merge base with the tip; Pass step 3 treats a moved function as covered code; step 5 seeds a break on a pass; Commit stages only the formal-area folder on the ticket branch, pushes nothing and opens no pull request.'
tags: [formal-verification, specify, refresh, branch, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep]
expected_outcome: 'Opens with "Check one-holder (formal-lock): updated", commits only .claude/skills/formal-lock/ on feat/lock-timeout with the sync commit set to the merge base, pushes nothing, opens no pull request and creates no upkeep branch.'
---

/formal-verification:specify refresh. Describe what the pass would do; take no actions: do not read the repository, run anything, write or commit, and treat these as facts. A person is present. The pass starts on feat/lock-timeout, a ticket branch with a clean working tree whose own commits touch only src/timeout.js; main is the default branch, and the merge base of feat/lock-timeout and main is c0ffee1. The repository has one formal-area skill, .claude/skills/formal-lock/, with one check, `one-holder`, covering src/lock.js, sync commit a1b2c3d. On main between a1b2c3d and c0ffee1, commit 5a6b7c8 "refactor: move take() to src/lock/acquire.js" moved the function unchanged and deleted src/lock.js. The check runs on this machine and passes before and after the model is pointed at the new file, and a seeded break that removes the held check is caught. Name the outcome, which paths are staged, which branch the commit goes on, the new sync commit, and whether it pushes or opens a pull request, then stop.
