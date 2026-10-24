---
bump: patch
---

### Fixed

- The pr-merge gate no longer drops the run's shared post-merge answer (`postMergeShared: unused:demotion-changed`) because an ordinary issue `github-actions[bot]` or the agent identity opened since the answer was computed. `babysit_merge_policy._demotion_changed` now counts such an issue only when `read_demotion` could count it as a demotion record: its body carries the demotion marker, or it may have been edited since it was opened (`updated_at` differs from `created_at`, or either is missing or unreadable). A known record still counts whenever it is updated, and a full or unreadable issue page still counts as changed. Each candidate then skips its own demotion read, floor and post-merge check.
