---
bump: patch
---

### Fixed

- `pr-merge`'s candidate listing no longer sleeps a fixed 15 s and 30 s or ends red on an outage.
  It runs through the new `.github/scripts/pr-merge/retry-call.bash`: at most three tries, waiting
  out a recorded rate stop or a capped, fully jittered backoff, within 60 s of waits in all. Each
  try also reads the open pull request count and fails when the listing does not match it, so a
  200 with items missing no longer reaches the gate. A listing still unknown ends the step green
  with a `::notice::` hold: the job lists, gates, files and merges nothing, and the next scheduled
  run lists again.
