---
description: "A repository whose default branch sets verification: standard in docs/conventions/planning.yaml: before round 2 the interview dispatches the fresh-context contradiction pass, which can catch Q3's 12:00 against C1. Needs --scaffold --allow-tools Bash Agent."
tags: [interview, setting, verification-level, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit, Agent]
expected_outcome: "Runs lib/read-verification.sh, reports verification: standard, dispatches a fresh-context contradiction pass before showing round 2, and writes no skip token"
---

/planning:interview me Schedule the nightly report export.

[Session state: an engineering session in the terminal lane. Constraint C1 (confirmed): exports never run during business hours, 08:00 to 18:00. Round 1 is answered: Q1 export format CSV; Q2 exports land in the reports bucket. Your draft round 2 asks Q3 (run time, recommended 12:00 so the export finishes before the afternoon review) and Q4 (retention, recommended 30 days).]

Show me round 2.
