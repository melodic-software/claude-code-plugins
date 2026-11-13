---
description: "A repository whose default branch sets verification: light in docs/conventions/planning.yaml: before round 2 the interview dispatches no contradiction-pass subagent and the round states the skip token. Needs --scaffold --allow-tools Bash Agent."
tags: [interview, setting, verification-level, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: light, dispatches no subagent, and shows round 2 with verification: skipped (light)"
---

/planning:interview me Schedule the nightly report export.

[Session state: an engineering session in the terminal lane. Constraint C1 (confirmed): exports never run during business hours, 08:00 to 18:00. Round 1 is answered: Q1 export format CSV; Q2 exports land in the reports bucket. Your draft round 2 asks Q3 (run time, recommended 12:00 so the export finishes before the afternoon review) and Q4 (retention, recommended 30 days).]

Show me round 2.
