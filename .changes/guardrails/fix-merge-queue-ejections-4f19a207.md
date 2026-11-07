---
bump: minor
---

### Added

- **block-unresolved-pr-merge**: a pull request that carries a hold label (`do-not-merge`, `pr-verify-failed` or `security: outside-actor`, matched without case) can no longer be merged, armed for auto-merge or enqueued through any merge path the guard covers. These are the labels the merge queue fails a group on, and the guard refuses as soon as it reads the pull request, so a later read that fails open cannot let the merge through. Sessions had queued pull requests already labeled `pr-verify-failed`, and each one failed its merge group.
