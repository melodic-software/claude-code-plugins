---
bump: minor
---

### Added

- The pr-merge gate adopts a person's pull request without the `adoption.idle-hours` wait when a person put it in the merge queue and the queue removed it for failed checks with no head change since: the enqueue's `actor` and `enqueuer` ids must both be `kind: human` on the trusted-actor list, and the head must be committed no later than that enqueue. The gate then re-enqueues it under every existing rule, the `merge.max-queue-ejections` cap and the head pin included, and records `eligibility.adoption` as `requeue-after-ejection`. `read_merge_queue` reports that enqueue as `ejectedEnqueue`; an unreadable queue or actor keeps the idle rule.
