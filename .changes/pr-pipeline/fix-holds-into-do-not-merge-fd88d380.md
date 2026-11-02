---
bump: minor
---

### Changed

- `do-not-merge` is the one veto ci-status reads. report-outcome labels a lanes App pull request
  that a person merges `do-not-merge`, and the `human-merge-hold` label is gone, with its ci-status
  step and the label readers in `enable-auto-merge.mjs` and the merge queue's label steps.
- ci-status no longer reads a lanes App pull request's body hold text or a member's veto comment;
  its lanes App step keeps the hold paths, cost, trusted-actor list, kill switch and the merge
  queue's pr-verify verdict read.
- ci-status no longer fails on a `pr-unblock/*` stop status, and the merge queue's early hold check
  no longer reads the head's statuses. `enable-auto-merge.mjs` still does not arm a stopped head.
- The address-feedback round cap, uncertain and disputed stops put `needs-session` on the pull
  request in place of `needs-human`; the open review thread still blocks the merge, and a session's
  answer on the thread restarts the lane. When the finding is security (CRITICAL or unrated), the
  new `feedback-round-cap-security`, `feedback-uncertain-security` and
  `feedback-disputed-security` stops keep `needs-human`, as do the intent, design and security
  question stops. The lost-runs reconciler no longer re-runs ci-status after a cleared stop.
