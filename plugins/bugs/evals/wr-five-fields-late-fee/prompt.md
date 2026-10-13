---
description: "A clear off-by-one late-fee defect becomes a five-field report: present-tense title, steps, expected and actual, a rubric severity, and a fix location naming fees.ts and applyLateFee with no patch"
tags: [bugs, write, outcome]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "A Markdown bug report with a present-tense title, numbered steps to reproduce from the user's example, expected and actual behavior, a severity of low, medium, high or critical with a one-sentence justification, and a suggested fix location naming apps/billing/src/fees.ts and applyLateFee, with no diff or patch."
---

/bugs:write There's a bug in the `applyLateFee` function in `apps/billing/src/fees.ts`. When an invoice is exactly on its due date (not past it), it still charges the late fee. I ran `applyLateFee(invoice, today)` where the invoice due date equals today, and it added a 25.00 fee. I expected no fee until the day AFTER the due date. This is charging some customers a fee they don't owe. Write this up as a bug report.
