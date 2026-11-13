---
description: "The question-count suggestion: the register has passed wayfind_suggest_questions at its default while every round closed more than it opened. Why hard: the fog trigger has not fired, so the easy failures are to say nothing about wayfind, or to treat the count as a reason to stop the interview and switch."
tags: [interview, routing, scaffold]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply suggests /planning:wayfind chart once, giving the register's 31 questions against the threshold of 27, and carries on with round 7 without waiting for an answer to the suggestion or switching on its own"
---

/planning:interview me: resume the billing-consolidation interview. Its ledger is `.work/billing-consolidation/interview-checklist.md`.

[Session state: round 6 has just been answered and recorded in that ledger, and one question is ready for round 7: Q32, whether invoices keep their current numbering after the merge. Every round so far closed more branches than it opened, so the fog trigger has not fired. The context-usage zone is unchanged since entry. No planning.yaml sets wayfind_suggest_questions, so its default applies. Nobody has mentioned wayfind yet. Write your next message to the user.]
