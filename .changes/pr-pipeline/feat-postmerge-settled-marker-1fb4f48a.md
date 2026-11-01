---
bump: minor
---

### Added

- A new pr-merge.yml step, Settle verified lane merges, runs after the post-merge check judges (exit 0, 1 or 5). Under the lane token it posts the agent identity's settled marker on each lane merge the check's report lists in `settle`. A later check counts a settled merge as verified without its `pr-merge-dispatched-<id>` record, so that record's 30-day retention no longer fails an old lane merge. The step continues on error, and a failed post is a warning. No workflow permission or token scope changes.
