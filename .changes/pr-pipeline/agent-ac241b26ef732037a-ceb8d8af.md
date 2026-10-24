---
bump: patch
---

### Fixed

- An address-feedback round whose reply job skipped `no-model-turn` no longer waits for a review or `pr-verify` run that may never come. `pr-feedback-dispatch.yml` also runs when a scheduled `pr-unblock-dispatch.yml` run completes (its half-hourly tick), and sweeps the open lanes App pull requests into `main`. The first head whose newest `pr-unblock / publish-feedback` check skipped `no-model-turn`, fewer than three times at that head, is decided and dispatched as for its newest completed review run, which the dispatched-run record names. A tick dispatches at most one head and keeps no dispatch record. The dispatcher stays a `workflow_run` run, so the trusted-trigger gate and the broker check it unchanged.

- Admission waits only on an open pull request in this repository that is for the issue: one GitHub lists as closing it (`closedByPullRequestsReferences`), or one whose body has the issue lane's `Refs: #<issue>` line. A pull request that only mentions the issue no longer defers admission, in `admit.mjs` or in work-unblock's sweep of `admission-deferred` issues.
- `publish-feedback` accepts an earlier fix on a retry. When the compare range holds no lane fix commit, each `VALID` thread's fix may be the newest earlier commit on the pull request that the lanes App made through the API with the push job's `Lane-Activity` trailer, committed after the thread's first comment, that changed the thread's path. Before, a round whose fix had landed but whose replies did not post left every thread open, and every retry ended `feedback-not-landed`.
