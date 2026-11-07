---
description: 'Legacy confirm 3. The fix criterion: the original symptom resolved and a regression check, read from context/fix.md, with the skill verifying rather than redoing the fix. The legacy prompt was the bare `/verification:confirm fix`; this case adds a narrated bug and fix, framed like the existing narration cases, since an empty workspace has no bug to confirm. reads-fix-context grades the Read of context/fix.md (with-only), names-regression the regression check in the reply, symptom-and-regression (llm) legacy expectations 1 and 3 verbatim.'
tags: [verification, confirm, narration, no-network, fix, routine]
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: 'A fix confirmation that restates the discount-tax symptom, ties the fix to it, reports the full suite as the regression check, and edits or re-fixes nothing; context/fix.md is read.'
---

/verification:confirm fix. Do not read the repository, launch, install or run anything; treat these as facts. Stage 1 already passed this conversation. The bug report: the invoice PDF shows the total without the 8% sales tax whenever the order has a discount code. The fix moves the tax step after the discount step in src/billing/total.ts. A unit test written before the fix, which failed on the old code, asserts the discounted total with tax, and it passes now. The full suite, 212 tests, passed before the fix and passes after it. Write the fix confirmation report, then stop.
