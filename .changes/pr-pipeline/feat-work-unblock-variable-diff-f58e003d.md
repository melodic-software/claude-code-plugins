---
bump: minor
---

### Added

- Repository variable check for work-unblock.yml's `publish-lane-level` (owner decisions Q113 (a) and Q115 (a)). Whenever the job holds a lane token, it lists every repository variable right after the mint and again after the publish, and fails red on any variable created, deleted or changed (value or `updated_at`) other than the configured `limits.lane-level.variable`, or when either listing is missing or incomplete; a failed first listing skips the publish. The state file holds digests and the logs name variables only, never values. The monitoring lane's new signal 14 (`lane-variables`) files a critical incident at once from the check's failure annotation.
