---
description: "Reshaping a wordy PR body keeps the completeness floor: the Closes line, the four named sections, the irreversible column drop, every decision, number, date and name, both asks, and plain before and after word counts"
tags: [writing, be-concise, outcome, completeness-floor]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read]
expected_outcome: "A shorter PR body that still opens with 'Closes #482', keeps the Summary, Fix, Verification and Related headings, states that dropping the discount_overrides column cannot be undone, keeps the 15-minute decision, Marta Quell's 2026-10-14 sign-off, the 410 ms and 120 ms figures and #455, keeps the backup step and the billing-review ask, and reports before and after word counts."
---

/writing:be-concise Rewrite this pull request description so reviewers can scan it. Return the rewritten body and the word counts; you do not need to repeat the original.

Closes #482

## Summary

So basically, after a fair amount of back and forth over the last couple of weeks, we have more or less landed on the decision that the pricing service should stop computing tier discounts on every single request and should instead read them from a cache that gets refreshed on a schedule. There were a number of options on the table, but at the end of the day the team decided to go with a 15-minute refresh interval, which Marta Quell signed off on during the review on 2026-10-14.

## Fix

What this change actually does is it adds a new `TierDiscountCache` class that is responsible for loading discounts from the `tier_discounts` table and holding them in memory. It is important to note that the migration included in this PR drops the old `discount_overrides` column from the `accounts` table, and this cannot be undone: once it runs in production, the data in that column is gone for good and there is no rollback path. Please make sure a backup snapshot exists before deploying.

## Verification

I ran the full test suite locally and everything passed, and I also ran a load test against staging where p95 latency for the quote endpoint went from 410 ms down to 120 ms, which is a really nice improvement.

## Related

This is related to the earlier work in #455 where we first started looking at the discount performance problem. Also, could someone from the billing team please review the migration specifically before this gets merged? We need that sign-off before merging.
