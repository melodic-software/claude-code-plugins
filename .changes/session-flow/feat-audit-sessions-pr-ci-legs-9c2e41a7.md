---
bump: minor
---

### Added

- `/session-flow:audit-sessions pr` also lists the CI lane runs pulled for the pull request's head branch, with each leg's metrics, when the `lane_transcript_sink` option is set.
- `lane_legs.py --branch <name>` keeps only the lane runs whose head branch is that name.
