---
bump: minor
---

### Changed

- The `do-not-merge` label is the one pull request hold. `merge-holds.mjs`, `enable-auto-merge.mjs`, `release-eval-hold.mjs`, `apply-patch.mjs`, `check-wip-cap.mjs` and the pr-unblock dispatchers no longer hold on body hold phrases, the lanes' hold line or member veto comments, and enable-auto-merge no longer turns a veto comment into the label. report-outcome holds a pull request with the label alone and writes no hold line into its body.
- ci-status's queue step reads no member veto and accepts merge-holds.mjs's `no hold path.` verdict line; the pr-merge and pr-verify wake steps read only the label.
- pr-unblock's body-refresh guard no longer refuses lane text for hold wording.
- ci-status's queue step and enable-auto-merge no longer read inline review comments or review threads, which fed only the member veto; issue comments and reviews are still read, and a list that does not read whole still refuses.
- A `do-not-merge` label the lanes App added for a member veto comment before this change stays on its pull request until a person removes it.
