---
bump: patch
---

### Fixed

- `pull-request` monitor: a re-arm at the Monitor deadline no longer loses a check that finishes between the full iteration's checks read and the new watch's first poll. The iteration writes its checks snapshot to a file and the watch starts from it (`BASELINE_FILE` in the poll script), so such a check is emitted once and checks already finished at the read are not reported again. The first arming still only records the checks on its first poll.
