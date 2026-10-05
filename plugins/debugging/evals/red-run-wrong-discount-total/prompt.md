---
description: "Phase 1 runs the checkout and observes the wrong total before any edit to cart.py"
tags: [debug, phase1-red-run]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Runs cart.py (or a test over it) and sees Total: 71.50 for the SAVE10 order before editing cart.py, and the reply reports the observed 71.50"
---

/debugging:debug customers who use the SAVE10 code pay more than 10% off their cart should cost. There's a sample order in orders/discounted.json and the totals logic is in cart.py. Find and fix it.
