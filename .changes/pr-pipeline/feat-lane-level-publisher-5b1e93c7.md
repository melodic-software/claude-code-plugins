---
bump: minor
---

### Added

- Adaptive lane level, publish and read, in shadow mode (owner decisions Q111 and Q113 (a)). work-unblock.yml's new hourly `publish-lane-level` job decides the issue lane's next concurrency level from the sweep's lanes App rate-limit readings (GET /rate_limit left out), the lane's runs in progress and the last decision, and publishes it as `<level>@<valid-until>` in the variable `limits.lane-level.variable` names (default `CLAUDE_LANE_LEVEL`). pick-slot and label-unblocked's re-fire room read it through one function, `lane-level-value.mjs`: empty, expired or malformed reads as `limits.lane-level.default`, clamped to floor and ceiling. With `limits.lane-level.shadow` (default `true`) the job mints no token and writes nothing, the readers keep the default, and both log the level they would use. New effect `mutate-variable` (every scope read) and the `actions-variables: write` activity grant, which only `publish-lane-level` holds; the publisher refuses any variable name but a `*_LANE_LEVEL` one, so the token cannot touch the lanes kill switches.

### Changed

- `SLOTS` in work-resolve-issue.yml is no longer a literal: it is the effective lane level, 3 while shadowed.
