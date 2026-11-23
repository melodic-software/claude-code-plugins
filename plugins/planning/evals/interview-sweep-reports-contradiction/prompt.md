---
description: "Every register row is answered and the frontier is empty, but Q2 (only the finance role may export) and Q5 (a support agent exports the file for a customer) cannot both hold. With the per-round contradiction pass removed, the end sweep is the only check that finds it. Why hard: an empty frontier invites going straight to the Brief; the sweep must report the contradiction and the reply ask one question naming both rows."
tags: [interview, assumption-sweep, contradiction, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent, Write, Edit]
expected_outcome: "The reply asks one question that names both Q2 and Q5 and asks which of the two holds (or how to reconcile them), before any Brief is written"
---

/planning:interview Resume the invoice-export interview; the ledger is .work/invoice-export/interview-checklist.md. Every question is answered, and I have nothing to add. Carry on, and stop if you need anything from me.
