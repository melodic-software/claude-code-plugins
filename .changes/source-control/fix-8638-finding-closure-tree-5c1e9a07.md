---
bump: patch
---

### Fixed

- `babysit_review_evidence` closes a review finding on a new head only when that head's tree differs: per-head finding counts now key on each lane run's `head_commit.tree_id`, so an empty commit (new sha, same tree) followed by a clean whole review no longer closes a finding, and no longer counts as a fresh head for `whole_review_clears`. A reviewed run with no readable tree unbinds the lane (`tree-unread`).
- The security lane's `critical-findings:` line lowers the blocking count only when no other review of the same tree reported a summary finding, so a re-run or an empty-commit review that comes back with `critical-findings: 0` no longer clears the earlier review's CRITICAL summary findings.
