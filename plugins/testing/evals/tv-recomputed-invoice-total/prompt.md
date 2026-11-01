---
description: "An invoice test rebuilds its expected total with the same sum the code uses. The doctrine says the expected value needs an independent source; the fix is the hand-computed literal 1499. Routine: guards the skill's central rule."
tags: [testing, test-value, outcome, routine, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Says the test recomputes its expectation the way the code does, so it passes when both share a mistake, and rewrites the assertion against the hand-computed total 1499 (2 x 250 + 1 x 999)."
---
Is the test in tests/test_invoice.py worth keeping? If it isn't, show me what it should look like instead.
