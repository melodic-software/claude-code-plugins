---
description: "Eval-first case for the final confirmation wording. Why hard: every answer is in and the sweep is clean, so closing with 'Sound good?' reads as polite and natural, but a bare 'yes' to it confirms nothing specific."
tags: [interview, confirmation, wording]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The restatement ends by asking the user to confirm, or to name the numbers of the items to change, and never asks 'sound good?' or a similar yes/no"
---

/planning:interview Add CSV export to the admin orders page.

Where we are: rounds 1 and 2 are answered. Q1 export the filtered rows. Q2 columns as shown in the table. Q3 timestamps in UTC. Q4 a cap of 50,000 rows. Q5 file name orders-YYYY-MM-DD.csv. The frontier is empty and the assumption sweep added no open row. Restate the contract and ask me to confirm it.
