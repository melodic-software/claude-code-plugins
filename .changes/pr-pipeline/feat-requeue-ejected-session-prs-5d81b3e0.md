---
bump: minor
---

### Added

- Adoption: a person's pull request skips the `idle-hours` wait when a trusted person's merge-queue enqueue was removed for failed checks (owner decision Q-REQ (a)). GitHub must have seen that head on the branch by the enqueue and not since, and no person may have commented or reviewed since the enqueue. The pr-merge gate records `eligibility.adoption` as `requeue-after-ejection` and then applies every gate rule unchanged, the `merge.max-queue-ejections` cap included.
