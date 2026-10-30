---
bump: patch
---

### Security

- `restart-consumer.sh` resolves an unpinned lane's `Lane telemetry: <lane>` issue, and its own `Lane telemetry: restart-consumer` fallback, only from issues the write identity opened, or the lane's `telemetry.author` when set. An exact-title issue another account opened is skipped and named in a warning, so an outside account can no longer capture a lane's telemetry home by opening an issue with the same title. A `telemetry.author` that is not a GitHub user login is a config error for an unpinned lane.
