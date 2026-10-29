---
bump: minor
---

### Added

- `review-venue --head <sha>` prints a `tests` line: `ci` when every test-lane check run on that commit passed, was skipped or ended neutral, and at least one passed, otherwise `local`. A skipped re-run from a label or body edit does not hide a lane's earlier failure.
- `ready --verify-local` runs the verify step's test suites locally even when CI's test lanes already passed on the head.

### Changed

- `/source-control:pull-request ready` no longer runs the test suites locally when CI's test lanes have already passed on the head it flips. It reports the verify step as `skipped (CI covers it)` and names the skipped suites. A draft's head still runs them, because a draft skips the test lanes.
