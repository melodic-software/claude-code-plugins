---
bump: patch
---

### Fixed

- A review finding whose only ask is to run tests CI runs no longer stops the address-feedback
  round. The adjudicator gains a `tests-only` verdict. On an `UNCERTAIN` reply to a non-security finding in a round that
  pushed no fix, the reply job settles it from the head's CI, which the select job records in
  `run.json`'s `ci`. The select job runs `scripts/plan-test-lanes.sh` over the pull request's
  files and reads the latest real run of each covering check: every planned `test-bash` and
  `test-python` leg, `test-node` and each `pr-test-windows` job. If every one passed and no
  unplanned test lane ran, a fixed reply says every check the plan selected passed and resolves the
  thread. If any test run on the head failed, the thread stays open with no escalation, and fix-ci
  takes the red head. If a check is pending, cancelled, missing or skipped, the round
  ends `feedback-unadjudicated` as before. No job gains a permission.
