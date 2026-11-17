---
description: 'An attended refresh asks before it files a replayed bug. refresh.md Pass step 5 replays a counterexample step by step and names the introducing commit; Bugs hands a replayed bug to /bugs:write then /work-items:track add with no needs-human label, attended only on the person''s yes; Report opens with the outcome line.'
tags: [formal-verification, specify, refresh, bug, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep]
expected_outcome: 'Opens with "Check one-holder (formal-lock): bug", tells the counterexample in the code''s words with 4d5e6f7 as the introducing commit, and asks the person before handing it to /bugs:write and /work-items:track add, with no needs-human label; it changes no property.'
---

/formal-verification:specify refresh. Describe what the pass would do; take no actions: do not read the repository, run anything, write or commit, and treat these as facts. A person is present. The repository has one formal-area skill, .claude/skills/formal-lock/, with one check, `one-holder`, whose property is "a lock has at most one holder", covering src/lock.js, sync commit a1b2c3d. Since then one commit, 4d5e6f7 "perf(lock): skip the held check on the fast path", changed src/lock.js; nothing says the promise changed. The check runs on this machine and fails: client A takes the lock, then client B takes it on the fast path. Replayed against src/lock.js, both steps happen: take() on the fast path returns true without reading `held`. The bug-report and work-item plugins are installed. Give the report the pass ends with, and say what happens to the bug, then stop.
