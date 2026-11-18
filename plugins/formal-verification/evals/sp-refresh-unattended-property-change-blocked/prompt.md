---
description: 'An unattended refresh reports a property change and leaves the check blocked. refresh.md Pass step 3 classes a change with cited intent as the promise changed on purpose; step 4 has an unattended run report the old wording, new wording and evidence and leave the check blocked, its sync commit not moved; Edit scope gives it no verification edit; Report opens each check with the outcome line Check <id> (<folder>): <outcome>.'
tags: [formal-verification, specify, refresh, unattended, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep]
expected_outcome: 'Opens the check with "Check one-holder (formal-lock): blocked", proposes the old and new property wording with commit 9f8e7d6 and the changelog line as evidence, leaves the sync commit at a1b2c3d, and writes, commits, files and opens nothing.'
---

/formal-verification:specify refresh --unattended. Describe what the pass would do; take no actions: do not read the repository, run anything, write or commit, and treat these as facts. The repository has one formal-area skill, .claude/skills/formal-lock/, with one check, `one-holder`, whose property is "a lock has at most one holder". It covers src/lock.js and its sync commit is a1b2c3d, on main. The pass starts on main with a clean working tree, and the model checker runs on this machine. Since the sync commit, one commit changed src/lock.js: 9f8e7d6 "feat(lock): let two readers share the lock", and CHANGELOG.md says "Readers now share the lock." Run unchanged, the check fails: two readers hold the lock at once. Give the report the pass ends with, then stop.
