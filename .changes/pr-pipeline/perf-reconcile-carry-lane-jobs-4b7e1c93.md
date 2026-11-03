---
bump: patch
---

### Changed

- maintenance-reconcile-lost-runs carries a lost pr-verify or pr-review-main run's attempt-1 job read in its settled-runs file while the run stays at attempt 1 with the same head and `updated_at`. A lane run deferred for want of one of the 3 re-run places is read once, not on every pass until it gets a place.
