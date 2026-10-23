---
bump: patch
---

### Fixed

- pr-merge.yml's `dispatch-full-run` and `post-merge-dispatch` jobs send the full-run dispatch at most three times: a rate-limited 403 or 429 waits retry-after seconds, else until one second past `x-ratelimit-reset` while none remain, else 60 s, and a request that got no response waits a full-jitter backoff, all within a per-job cap (180 s and 300 s) that keeps each job inside its timeout. Any other answer, a 5xx included, is not sent again, since the run may exist. A dispatch that still fails ends the job green with a warning naming the merge commit, uploads no `pr-merge-dispatched-<id>` record and skips the wait, so the next push or scheduled run starts the run instead of a red job.
- The wait for the dispatched run reads its status every three minutes instead of every minute, 13 reads over 39 minutes.
