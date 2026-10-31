---
bump: patch
---

### Fixed

- `pr-merge`'s candidate listing no longer sleeps a fixed 15 s and 30 s or ends red on an outage.
  It runs through the new `.github/scripts/pr-merge/retry-call.bash`: at most three tries, waiting
  out a recorded rate stop or a capped, fully jittered backoff, within 60 s of waits in all. Each
  try also reads the open pull request count and fails when the listing does not match it, so a
  200 with items missing no longer reaches the gate. A listing still unknown ends the step green
  with a `::notice::` hold: the job gates, merges, re-fires and clears nothing, and the next
  scheduled run lists again. A listing that reaches its limit of 1000 ends the job red at once with
  no retry. The re-fire and escalation-clear steps skip on a red listing too.
- A held `pr-merge` run still writes the `pr-merge-summary` artifact, with `listing_held` and
  `listing_held_reason`, and its sweep cost line. It files, dequeues and merges nothing: the next
  run that lists records a failed lane merge and dequeues the lane's entries.
- `retry_call` repeats only a call passed `--read`; without it the command runs once, so a write
  is never repeated.
- `maintenance-monitor-signals` has a new signal, `12 listing held`: 4 scheduled or hand-started
  `pr-merge` sweeps in a row whose listing held raise a rolling issue. Signals 5 and 8 read the
  newest sweep that listed, and one over 70 minutes old for any reason is a gap for them, read as
  no sweep. Signal 3 counts a rate-limited hold still unbroken at the monitoring run.
