---
bump: minor
---

### Added

- **block-unresolved-pr-merge**: a pull request that carries a hold label can no longer be merged, armed for auto-merge or enqueued through any merge path the guard covers. The new `merge_guard_hold_labels` option lists the labels, matched without case; the default holds `do-not-merge`, `pr-verify-failed` and `security: outside-actor`, the labels the merge queue fails a group on, and an empty value holds on none. Sessions had queued pull requests already labeled `pr-verify-failed`, and each one failed its merge group.
