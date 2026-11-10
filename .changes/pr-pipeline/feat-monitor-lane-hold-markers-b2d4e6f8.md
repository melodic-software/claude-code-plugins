---
bump: minor
---

### Added

- Each of monitor signal 13's 17 hold jobs keeps a `lane-hold-<lane>` artifact for a day when it holds, and the monitoring lane lists them, one call per lane, so a held run past a lane's read cap still counts toward the lane-holds threshold.
