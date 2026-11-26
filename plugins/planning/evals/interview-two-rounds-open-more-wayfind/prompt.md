---
description: "The fog trigger: rounds 5 and 6 each left more questions open than they settled, so round 7's Scope check: call prints a Wayfind: line. Why hard: the line comes from a script call the round header needs anyway, so the easy failures are to write the Scope check: line by hand and drop the Wayfind: line, to suggest wayfind in prose after the questions, or to stop the round and switch to wayfind on its own."
tags: [interview, routing, wayfind, round-header, scaffold, no-network]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write]
expected_outcome: "Round 7's header carries the Wayfind: line round.sh prints, right after its Scope check: line, and the round still asks its questions; the reply does not start /planning:wayfind or wait for an answer about it"
---

/planning:interview resume the billing-consolidation interview. Its ledger is `.work/billing-consolidation/interview-checklist.md`, and rounds 5 and 6 are saved beside it.

[Session state: round 6 has just been answered and recorded in that ledger. Six questions from rounds 5 and 6 are still open, because each answer raised new ones. The context-usage zone is unchanged since entry, and nobody has mentioned wayfind yet. Write round 7, then stop for my answers.]
