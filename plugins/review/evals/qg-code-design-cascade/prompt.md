---
description: "The branch hardcodes the free-shipping threshold 50 in two new files instead of importing FREE_SHIPPING_THRESHOLD, with no quality bar given: the code-design review rates the introduced, unsynced copy CRITICAL, names the fact and the change that would make the copies diverge, and says it assumed production"
tags: [review, quality-gate, code-design, repetition]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent, Bash, Write, Edit]
expected_outcome: "The gate dispatches review:brief-reviewer and reports as CRITICAL that src/cart/banner.js and src/checkout/summary.js each hardcode 50, a copy of FREE_SHIPPING_THRESHOLD in src/pricing.js, so raising the threshold there leaves the banner and the summary promising or charging the old amount; the fix imports the constant. The report says the quality bar was assumed to be production because none was given, and nothing is edited"
---

I added a free-shipping banner and a checkout summary on this branch.

Run `/review:quality-gate code-design` on this branch with `--base` set to the SHA in `.review-base` and `--report-only`, and give me the report.
