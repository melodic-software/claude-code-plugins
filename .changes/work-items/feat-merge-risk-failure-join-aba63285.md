---
bump: minor
---

### Added

- `/work-items:measure-delivery --merge-risk` counts, per merge-risk `demote` group, the rated
  merges and those later met by a post-merge demotion record, a silent-revert canary record or a
  revert on the default branch, with a per-lane breakdown where the rating names the lane run. It
  prints "not enough failures to compare" in place of a rate while either group has fewer than 5
  failures, reads the forge only on GitHub, and writes nothing.
