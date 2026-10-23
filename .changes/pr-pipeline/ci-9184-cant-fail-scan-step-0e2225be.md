---
bump: patch
---

### Added

- `ci-status` now gates tests that cannot fail. On a pull request or merge group, the `check-plugins` gate `cant-fail-scan` runs `/testing:audit`'s scan on each changed test file, and reports not applicable when the diff changes none. When there is no diff base (the schedule, a dispatch, or a pull request or merge group that resolves to the whole tree), a new `check-tests` job scans the whole tree; with a diff base it returns at once ([#9184](https://github.com/melodic-software/claude-code-plugins/issues/9184)).
