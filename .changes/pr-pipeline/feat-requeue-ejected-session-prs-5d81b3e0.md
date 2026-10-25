---
bump: minor
---

### Added

- Adoption: a person's pull request skips the `idle-hours` wait when a trusted person's merge-queue enqueue of its unchanged head was removed for failed checks (owner decision Q-REQ (a)). The pr-merge gate records `eligibility.adoption` as `requeue-after-ejection` and then applies every gate rule unchanged, the `merge.max-queue-ejections` cap included.
