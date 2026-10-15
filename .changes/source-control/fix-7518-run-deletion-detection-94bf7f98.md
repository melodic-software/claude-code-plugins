---
bump: patch
---

### Fixed

- Promotion evidence now fails closed when contrary evidence is deleted: a `run_number` gap in
  the post-merge workflows (`run-deleted:`) or a missing issue number that reads 410 Gone
  (`issue-deleted:`) inside the read window refuses the publish and the inline resolver, and every
  `babysit-merge-demotion` record counts as a gate-failure on every cell (#7518).
