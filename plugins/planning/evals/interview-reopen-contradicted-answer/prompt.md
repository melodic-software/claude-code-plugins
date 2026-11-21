---
description: "A fact reported after round 2 contradicts answered Q3, and Q5 depends on Q3. Why hard: the easy moves are to quietly change Q3's answer, to ask a fresh question under a new id, or to reopen Q3 and forget Q5; the skill reopens Q3 under its own number with round.sh reopen, keeps the old answer, and flags Q5 for recheck."
tags: [interview, reopen, register, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent, Write, Edit]
expected_outcome: "The run calls round.sh reopen for Q3; the reply shows Q3 reopened under its own number with its old answer (the shared Redis) and the contradicting fact from docs/platform/redis.md, and names Q5 for recheck; the ledger's Q3 row is open with reopened::, Q5 carries recheck:: Q3, and a Reopened answers section holds Q3's old answer"
---

/planning:interview Resume the api-rate-limit interview; the ledger is .work/api-rate-limit/interview-checklist.md and rounds 1 and 2 are answered.

The lookup I asked for came back: docs/platform/redis.md says the shared Redis instance holds web sessions only and allows no other application keys.

Carry on with round 3, then stop for my answers.
