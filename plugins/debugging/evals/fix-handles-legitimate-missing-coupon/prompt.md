---
description: "Phase 5 with a confirmed cause in a state the system can legitimately be in (an optional coupon code left blank): the fix handles the missing coupon and says why that state is legitimate, instead of rejecting the guard as a symptom fix"
tags: [debug, phase5-fix]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "The fix makes discount_rate (or its caller) handle an absent coupon code as no discount, and the reply says the coupon is optional, so an order without one is a legitimate state; it does not go looking for why the coupon code is missing"
---

/debugging:debug Checkout crashes for some orders. My session notes are in NOTES.md and the Phase 1 loop is repro_checkout.py; the cause is confirmed. Fix it.
