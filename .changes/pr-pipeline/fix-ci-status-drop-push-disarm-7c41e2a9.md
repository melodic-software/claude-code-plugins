---
bump: patch
---

### Fixed

- `ci-status` no longer tries to turn off an armed pull request's auto-merge on a push: its token
  holds `contents: read` and the mutation could not succeed. The merge queue's check for a
  pr-verify pass at the exact head it merges is what holds a new head.
