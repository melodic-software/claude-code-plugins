---
bump: patch
---

### Changed

- `pr-feedback-dispatch.yml`'s `rerun-ci-status` re-runs a head's ci-status once, after the last review lane finishes, instead of once per lane: while the other lane's newest run on the head is still going it stops after one read, since ci-status would still be red and that lane's completion starts the job again. A head with no run of the other lane re-runs on one lane. A ci-status that started after both lanes finished, or a re-run already queued, is left alone. The job list is read once, and each 60-second poll reads only the run. A read refused by the token's primary rate limit (403 or 429 with `x-ratelimit-remaining: 0`) waits until one second past `x-ratelimit-reset` inside the same 10-minute cap instead of failing; a reset past the cap ends the job green with a warning.
