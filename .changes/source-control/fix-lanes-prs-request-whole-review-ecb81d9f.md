---
bump: patch
---

### Fixed

- `babysit_whole_review.wanted` also requests a whole review for a `review-path:` hold whose bound
  security review counts open findings below CRITICAL that a clean whole review of the head
  closes, such as threads the lanes App resolved. Before, only a CRITICAL `security-finding` hold
  qualified, so such a hold waited for a person.

### Added

- `babysit_whole_review.py request` answers the record line for a whole review of `--head` under
  the merge gate's caps (once per head, `MAX_TOGGLES`, one per run, the running-jobs and
  rate-limit floors), reading the prior reasons comment on stdin; `toggle` drafts the pull request
  and marks it ready again. The gate and enable-auto-merge share `babysit_whole_review.request`.
- `babysit_verify_evidence.py evidence --lane-reviews` reports `wholeReviewWanted`, so native
  auto-merge requests the gate's whole review for a lanes App pull request.
