---
description: "A repository whose default branch sets verification: light in docs/conventions/debugging.yaml: the fix is made and the mechanical checks run, but no fresh-context outcome verifier is dispatched, the record writes the skip token, and the outcome is left unverified rather than judged by the context that produced the fix"
tags: [debug, setting, verification-level, scaffold]
runs: 3
max_turns: 50
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write, Agent]
expected_outcome: "Runs lib/read-verification.sh and reports verification: light; fixes cart.py with a regression test; dispatches no outcome verifier; writes verification: skipped (light)."
---

/debugging:debug customers who use the SAVE10 code pay more than 10% off their cart should cost. There's a sample order in orders/discounted.json and the totals logic is in cart.py. Find and fix it.
