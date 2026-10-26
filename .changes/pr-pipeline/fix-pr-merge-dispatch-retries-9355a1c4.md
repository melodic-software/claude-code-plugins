---
bump: patch
---

### Fixed

- pr-merge.yml's full-run dispatch, in both jobs, now also sends again on Go's `net/http: TLS handshake timeout`, which fails before the request is written; a rate limit still stops the step red with no further send. The re-run step's `rerun-failed-jobs` POST and the full-run wait's send to post-merge-demotion-alert.yml take the same retry: at most three attempts, sent again after a capped full-jitter wait (up to 10 s, then 20 s) only when gh's error shows the request never left. A rate-limited alert send now stops red, sent once. The warning after a dispatch that never started a run now says a scheduled pr-merge run starts one only for a lane merge, and any other merge waits for the next push or pr-require-checks' own schedule.
