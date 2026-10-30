---
bump: patch
---

### Fixed

- A hard-killed OTEL prune no longer leaves the `otelcol-contrib` Collector stopped and every later prune reporting `action=noop-locked`. The `.prune-in-progress` owner token now records the holder's pid and start time; a later run takes over a sentinel whose holder is gone (or, with no token, one older than an hour) and logs it. Every run that finds no live prune holding the sentinel starts a stopped Collector, the no-op and `--scrub-cold` paths included. A live prune that holds the sentinel for over an hour fails the run with `action=error-lock-held` and exit 1, so the scheduled task's result shows it.
