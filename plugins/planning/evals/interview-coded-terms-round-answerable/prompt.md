---
description: "A resumed interview whose ledger names every constraint, answer and coined term by code (C1 to C3, Q1 to Q4, R-cap). Why hard: the ledger is in the agent's context, so 'Checked against: C1, C3' or 'rests on Q3' reads as complete to it, while a reader with none of the session's knowledge cannot answer; the easy repair, a lay rewording, drops the technical terms the owner uses."
tags: [interview, plain-names, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "The next round re-asks the unanswered rerun-cap question and asks the open branches, and every constraint, earlier answer and coined term appears with its plain name (no bare C1 to C3, Q1 to Q4 or R-cap), with head SHA, pr-merge lane and ci-status kept as written, so a reader with no prior session context can answer it"
---

/planning:interview me Resume the review-reruns interview; the ledger is .work/review-reruns/interview-checklist.md. Show me the next round, written for a reviewer who has not seen this session, then stop for my answers.
