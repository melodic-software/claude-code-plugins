---
bump: patch
---

### Added

- `ci-status` now gates tests that cannot fail. On a pull request or merge group, the `check-plugins` gate `cant-fail-scan` runs `/testing:audit`'s scan on each changed test file, and reports not applicable when the diff changes none. On the schedule and on dispatch, a new `check-tests` job scans the whole tree; `ci-status` counts its skip on a pull request or merge group as success ([#9184](https://github.com/melodic-software/claude-code-plugins/issues/9184)).
