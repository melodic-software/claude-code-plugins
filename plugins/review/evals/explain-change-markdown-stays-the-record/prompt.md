---
description: "Requested explainer of a PR that moves coupons to the cart and drops orders.coupon_code delivers the markdown digest (Why, Before and after, Risk map, Where to focus, File by file) with a checked risk map whose rows each give area, level and why, rates the dropped column HIGH or above, and builds and posts nothing"
tags: [review, explain-change]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
expected_outcome: "The reply is the markdown digest of acme/storefront#77 with Why, Before and after, Risk map, Where to focus and File by file sections. The risk map has one row per area with an area, a LOW to CRITICAL level and a why, checked by a review:brief-reviewer agent, and a row rates the migration that drops orders.coupon_code HIGH or CRITICAL because the stored codes are lost. Medium is terminal, so no page is built, and nothing is posted to the pull request"
---

/review:explain-change 77

The pull request is 77 of acme/storefront, and I am asking for this explainer: I want to know why it exists, what changed before and after, and where to focus.

This run has no GitHub access and no shell, so the reads and the policy check were done for you. The pull request's facts are saved in .claude-lane/pr/facts.json and its diff in .claude-lane/pr/pr.diff; use .claude-lane/pr as the run's directory and do not read the pull request again. The policy script printed:

```json
{"action": "build", "triggers": ["risk-path"], "medium": {"value": "terminal", "source": "user", "explicit": true, "report": ["medium: terminal (your setting)"]}}
```

Read only those files and post nothing.
