---
bump: patch
---

### Fixed

- pr-merge.yml's full-run dispatch no longer waits out a rate limit and sends again: any 429, or a 403 with a retry-after, remaining 0 or a message naming a rate limit, fails the step red, naming the pool and the reset (with no header time, a minute on for a secondary limit and an hour on for any other, as the lanes' rate guard decides), and the candidate listing fails red on a rate limit instead of retrying it. enable-auto-merge's resend is pinned by a test never to resend an arm GitHub answered with 403 or 429. When a gate reader it starts (the per-pull-request verifier read or the lane-room read) exits 75 on a rate limit, enable-auto-merge sends no further read, arm, disarm or note that run and fails red with the guard's error naming the pool and the reset. Either post-merge check (the post-merge-dispatch job's and the merge job's) that exits 75 on a rate limit now fails its job red once its outputs are written, with needs-dispatch false, and no dispatch, re-run or gate follows it. A rate limit that stops post-merge-dispatch (its check or its dispatch) goes to the merge and enable-auto-merge jobs as its `rate-limited` output, naming the pool and the reset; each then ends red at its first step and sends nothing to GitHub.
