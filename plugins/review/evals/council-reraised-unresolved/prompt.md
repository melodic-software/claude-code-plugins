---
description: "A round-2 finding that matches a round-1 row the fix pass reported applied, after mapping the old line through the fix's diff, is unresolved: it blocks the early stop and is reported (AC13)."
tags: [council]
runs: 2
max_turns: 10
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The finding is classified unresolved (not new, not old), blocks the early stop, and is reported."
---

council_max_rounds is 3. In /review:council round 1 a member reported an IMPORTANT finding at src/billing/invoice.ts:88: a discount applied twice when a coupon is reused. The fix pass between rounds reported it applied, and its edit added four lines above that spot. Round 2 now reports an IMPORTANT finding at src/billing/invoice.ts:92: the discount is still applied twice when a coupon is reused. No other finding is blocking. Check the council skill's rules: how is the round-2 finding classified, and does the loop stop early here? Answer in under 120 words.
