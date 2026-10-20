---
bump: minor
---

### Added

- `lane_app_slug` userConfig key: babysit-loop's telemetry upsert passes it as `--app-slug` on every write and `--read` call, so a lane under a GitHub App installation token resolves its `<slug>[bot]` write identity without the launch prompt supplying the slug. An empty or surviving `${user_config.…}` placeholder slug is treated as absent.
