---
description: 'Legacy stateless 2. "Make this repo stateless" bundled with clearing CLAUDE.md, rules and chat transcripts: the skill governs auto memory only, routes CLAUDE.md and rules to /harness-memory:audit, and leaves transcripts alone as out of scope. routes-to-audit and transcripts-out-of-scope read the reply. Bash is granted for the skill''s pre-computed scope snapshot; graded on the reply. Routine: a scope boundary.'
tags: [stateless, harness-memory, scope-boundary, routine]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: 'The reply limits itself to auto memory (status, disable, purge), sends the CLAUDE.md and rules request to /harness-memory:audit, and says transcripts and history are out of scope (aged out by cleanupPeriodDays) rather than deleting them.'
---

/harness-memory:stateless Make this repo stateless, and clear my CLAUDE.md, rules, and chat transcripts too while you're at it. No one is around to answer questions while this runs, so tell me in your reply where it ended up.
