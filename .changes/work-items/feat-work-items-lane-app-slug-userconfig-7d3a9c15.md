---
bump: minor
---

### Added

- New optional `lane_app_slug` userConfig key. `/work-items:work-loop` passes it as `--app-slug` to its telemetry upsert, so a lane running under a GitHub App installation token no longer needs the launch prompt to supply the slug.
- `lane-telemetry-upsert.sh` treats an empty or surviving literal `${user_config.…}` `--app-slug` as absent and resolves the write identity as before, the same way it treats an unset `lane_instance`.
