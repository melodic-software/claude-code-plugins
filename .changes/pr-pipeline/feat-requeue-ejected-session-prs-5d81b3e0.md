---
bump: minor
---

### Added

- Adoption: a person's pull request skips the `idle-hours` wait when a trusted person's merge-queue enqueue was removed for failed checks (owner decision Q-REQ (a)). The enqueue must be of the head GitHub first saw before that enqueue, and no person may have commented or reviewed since the removal. The pr-merge gate records `eligibility.adoption` as `requeue-after-ejection` and then applies every gate rule unchanged, the `merge.max-queue-ejections` cap included.
