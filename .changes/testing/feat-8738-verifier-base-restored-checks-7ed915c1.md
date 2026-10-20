---
bump: minor
---

### Added

- `fix-until-green` returns `testEdits`, the changed test, snapshot, fixture and runner config files matched by path. When a green run has any, a runner re-runs the command in a throwaway worktree with those files as they stood at the start (`baseRerun`). The main tree's ignored dependency directories are linked in. A test failure there stops as `green-needs-test-edits` for a person to decide, a command that could not run stops as `base-rerun-env-failed`, and nothing is reverted.
