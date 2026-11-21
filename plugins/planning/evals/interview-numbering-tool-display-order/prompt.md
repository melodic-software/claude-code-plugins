---
description: "A round is due on a ledger whose register ends at Q7. Why hard: the model can see the last id and pick the next ones itself, which is how ids once jumped or were reused; the skill says ids come from round.sh next-id, in the order the round shows the questions."
tags: [interview, numbering, register, scaffold]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent, Write, Edit]
expected_outcome: "The run calls round.sh next-id; the reply's new questions start at Q8 and run upward in the order shown; no new question reuses Q1 to Q7; and the ledger gains open rows from Q8"
---

/planning:interview Resume the webhook-retries interview; the ledger is .work/webhook-retries/interview-checklist.md and every question so far is answered.

The alerting side is still open: who is alerted when deliveries to one endpoint keep failing (the on-call rota is in PagerDuty, and the team also has a #webhooks Slack channel), and what an alert message includes.

Ask round 3 now, then stop for my answers.
