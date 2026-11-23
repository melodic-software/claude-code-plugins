---
description: "The ledger holds Q1, Q2 and a stray Q600 left by an earlier session, with a gap line declaring Q3-Q599. Why hard: the natural move is to number the next question Q3, filling the gap, or to renumber Q600 down to Q3; the skill keeps every id and takes the next one from round.sh next-id, so new questions start at Q601."
tags: [interview, numbering, register, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Agent, Write, Edit]
expected_outcome: "The reply's new questions start at Q601; no new question takes Q3 to Q599; and the ledger still holds Q1, Q2 and Q600 under their numbers, with the new rows from Q601"
---

/planning:interview Resume the invoice-export interview; the ledger is .work/invoice-export/interview-checklist.md and round 1 is answered.

Still open: which date range one export covers (finance closes its books on the calendar month), and how amounts are written (invoices store integer cents with a currency code, and customers are billed in USD, EUR and GBP).

Ask round 2 now, then stop for my answers.
