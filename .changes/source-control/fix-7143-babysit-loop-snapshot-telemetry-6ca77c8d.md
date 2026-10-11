---
bump: patch
---

### Fixed

- `babysit-loop` takes its cycle-start snapshot through a new `lane-snapshot.mjs`, which pages every open pull request and issue and exits non-zero on a read failure (3) or on pull-request and issue lists that disagree on two reads (4). On a failed snapshot the cycle takes no drain exit and holds `cycle` and `backoff_level`, so a failed read is never an empty queue; it counts toward the no-progress streak, so a snapshot failure that never clears raises the stall escalation (#7143).
- `babysit-loop`'s telemetry upsert is now `telemetry-upsert.sh`, with distinct exit codes (3 invalid input, 4 no gh, 5 a failed API call, 6 an unconfirmed write) and a read-back byte-compared with the body sent, so a stale or overwritten comment no longer passes as this cycle's telemetry (#7143).
