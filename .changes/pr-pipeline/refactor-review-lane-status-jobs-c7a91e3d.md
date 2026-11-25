---
bump: none
---

ci-status's cost-hold step reads the review lanes' status job names and its review-lane workflow test from the hold config's merge-holds.mjs (REVIEW_LANES, laneChange), and clear-escalations.mjs LANE_RECORDS takes its job names from REVIEW_LANES, in place of two copies of the table; which holds clear is unchanged.
