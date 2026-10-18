---
bump: minor
---

### Added

- `/source-control:worktree cleanup [<path>...] [--dry-run]` takes explicit worktree paths and runs the same classification and every Step 4 guard on exactly those worktrees, skipping the repository-wide inventory and root scan.
- A bare `cleanup` in a session that created, entered or merged a PR from one worktree asks whether to clean that worktree or sweep the whole repository before inventorying, and says so up front when the scoped worktree is the session's own.

### Changed

- `cleanup` Step 4c runs the landed-branch deletion and the current-worktree removal itself on Linux and macOS after the Step 4 confirmation and a passed stranded-work guard. It still emits them for the user on Windows or when a hook blocks the command.
