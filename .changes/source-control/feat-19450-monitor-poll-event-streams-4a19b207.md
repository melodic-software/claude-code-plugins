---
bump: minor
---

### Added

- `pull-request` monitor: `monitor-poll.sh` attaches a persistent `gh event listen` stream before its initial poll for immediate PR wakeups (coalescing bursts into one conditional poll pass, running `source-control-review-threads` immediately on submitted reviews, and running a `--safety-interval` safety poll defaulting to 600s) with automatic fallback to `--interval` polling when `gh event` is absent, returns an error, fails to attach, exits mid-watch, or is disabled via `--no-events` or `MONITOR_POLL_EVENTS=0`.
