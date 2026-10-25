---
bump: minor
---

### Added

- The pr-merge gate adopts a person's pull request without the `adoption.idle-hours` wait when a person put it in the merge queue and the queue removed it for failed checks with no head change since. Four conditions apply:
  - the enqueue's `actor` and `enqueuer` ids must both be `kind: human` on the trusted-actor list;
  - GitHub must have first seen the head (its earliest GitHub Actions check suite on the PR's branch) no later than that enqueue;
  - no person may have commented, reviewed or commented inline since the removal;
  - an unreadable queue, check-suite listing or discussion keeps the idle rule.

  The gate then re-enqueues the pull request under every existing rule, including the `merge.max-queue-ejections` cap and the head pin, and records `eligibility.adoption` as `requeue-after-ejection`. `read_merge_queue` reports that enqueue and the removal's time as `ejectedEnqueue`.
