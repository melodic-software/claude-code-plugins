---
bump: minor
---

### Added

- **lanes:** a new optional `lane_app_slug` option holds the GitHub App slug the lanes run `gh` under. The `consume-restarts` invocation passes it to `restart-consumer.sh` as `--app-slug`, and the `telemetry-upsert.sh` guidance passes it on every call, so an operator whose lanes write under an App installation token no longer has to type `--app-slug` on each run. The README options table lists it.

### Changed

- **lanes:** `restart-consumer.sh` and `telemetry-upsert.sh` read an unrendered `${user_config.lane_app_slug}` placeholder as no slug instead of refusing it with exit 3, so the always-passed option is harmless when unset. `restart-consumer.sh` also accepts an empty `--app-slug` value, which it used to refuse with exit 3, and reads it as no slug, as `telemetry-upsert.sh` already did. A bare trailing `--app-slug` with no value is still refused.
