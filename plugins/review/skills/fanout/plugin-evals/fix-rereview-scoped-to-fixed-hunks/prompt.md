---
description: "The re-review a fanout fix pass requires after correctness fixes covers only the hunks those fixes changed, not the whole branch diff. Read is not granted, so the with-arm measures what the SKILL.md hub carries."
tags: [pocock-r5, fix-pass]
runs: 3
max_turns: 10
allowed_tools: [Skill]
expected_outcome: "The plan keeps the post-fix re-review required for the two correctness fixes and scopes it to the hunks those fixes changed (src/auth/session.ts lines 84-95 and src/billing/invoice.ts lines 208-215), not the full 2,400-line branch diff."
---

I ran the review fanout on my feature branch (about 2,400 changed lines across 37 files) and then its fix pass. The fix pass just applied fixes for two correctness findings: a missing null check at src/auth/session.ts:88 (the fix changed lines 84-95) and an off-by-one at src/billing/invoice.ts:212 (the fix changed lines 208-215). A third finding was cleanup-class and went through simplify. Before I commit, what re-review does the fix pass call for now? Say exactly what code it covers and which reviewers look at what. Don't run anything; lay out the plan in under 200 words.
