---
bump: minor
---

### Added

- `animation.gesture.distance_threshold` (default `0.4`): the fraction of its own travel past which a dragged element dismisses on release.
- The gesture reference's `linked-progress` rule: every visual tied to a gesture follows the gesture's one progress value.

### Changed

- Gesture tracking takes no spring or transition, and a drag that does not dismiss springs back fast.
- Under reduced motion, pointer tracking stays; release drops momentum and bounce and adds no position settle.

### Removed

- `scripts/check-emilkowalski-drift.sh` and its weekly drift-workflow row: the standard upstream record now covers this source.
