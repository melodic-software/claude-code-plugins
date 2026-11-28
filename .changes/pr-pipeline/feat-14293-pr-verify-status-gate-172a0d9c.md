---
bump: minor
---

### Added

- A `pr-verify` commit status on same-repository pull request heads and merge-group commits, so a merge-queue ruleset can require it. pr-verify's `report-status` job posts success for a PASS or PASS-NOTES and failure for a FAIL unless a trusted approval of the head lifts it (`merge-holds.mjs` `pathLifters`); `ci-status` posts success for an author pr-verify does not judge and the verify gate's decision on the merge-group commit; `pr-dispatch-feedback.yml`'s `lift-verify-fail` job posts success when a trusted approval of the head finds its status anything but success. `release-publish-plugins.yml` queues a release pull request only once its head's `pr-verify` status is success.

### Changed

- In the merge queue, the `merge.max-verify-fails` cap (`verify:repeated-fail`) now holds a pull request pr-verify judges that is not the lanes App's (an owner-login one included) like any FAIL, instead of only warning (owner decision 2026-11-28).
- `maintenance-reconcile-lost-runs` re-runs a pr-verify run the lanes kill switch stopped up to 30 days after it started, not only within its 24-hour lookback, when the run follows an open head's newest checks run, so a head whose run a switch stopped more than a day before it cleared still gets its `pr-verify` status.
