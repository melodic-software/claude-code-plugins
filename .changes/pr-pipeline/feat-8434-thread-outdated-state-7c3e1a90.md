---
bump: minor
---

### Added

- address-feedback's thread file gives each kept thread `is_outdated`, true only when GitHub reports the review thread's `isOutdated` true, beside its `review_commit`, so a lane working a thread from an earlier review sees that its line may be stale. Edit scope still keys on paths alone.
