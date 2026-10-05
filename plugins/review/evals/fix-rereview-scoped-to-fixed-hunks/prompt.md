---
description: "The re-review a fanout fix pass requires after correctness fixes covers only the hunks those fixes changed, not the whole branch diff. Guards against a regression: the base model already scopes it. The prompt names /review:fanout and asks the agent to check its rules, so the with-arm loads the skill; Bash is listed because the skill's pre-computed context runs gh pr list, and a Bash denial fails the whole skill load (run with --allow-tools Bash)."
tags: [pocock-r5, fix-pass]
runs: 3
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The plan keeps the post-fix re-review required for the two correctness fixes and scopes it to the hunks those fixes changed (src/auth/session.ts lines 84-95 and src/billing/invoice.ts lines 208-215), not the full 2,400-line branch diff."
---

I ran /review:fanout on my feature branch (about 2,400 changed lines across 37 files) and then its fix pass. The fix pass just applied fixes for two correctness findings: a missing null check at src/auth/session.ts:88 (the fix changed lines 84-95) and an off-by-one at src/billing/invoice.ts:212 (the fix changed lines 208-215). A third finding was cleanup-class and went through simplify. Before I commit, check what the fanout skill's fix action says: what re-review does the fix pass call for now? Say exactly what code it covers and which reviewers look at what, in under 200 words.
