---
description: "The confirmation of an engineering interview whose ledger has a line for every part: a hedged answer and a captured assumption, topic-tagged answers, an agreed term and ADR outcomes, plus one out-of-scope item the user named. Why hard: the familiar shape is a flat recap of every answer followed by the check output, so the easy failures are to put the hedged answer among the settled ones, to list the parts in another order, or to report the checks by script name and exit code."
tags: [interview, confirmation, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "The confirmation shows its parts in order (Problem, Needs your eye with the hedged finance-only answer and the row-count assumption, the answers grouped by topic, Out of scope with the PDF export, Terms and ADRs, Checks in plain words, then one Next pointer), names no script and no exit code, and ends by asking the user to confirm or name the Q numbers to change"
---

/planning:interview resume the invoice-export interview; its ledger is `.work/invoice-export/interview-checklist.md`.

[Session state: an engineering session in the terminal lane. Every question is answered and the assumption sweep added nothing. In round 2 the user said a PDF export stays out of this change and goes to a later issue. No confirmation has been shown yet. Write the confirmation now, then stop for my reply.]
