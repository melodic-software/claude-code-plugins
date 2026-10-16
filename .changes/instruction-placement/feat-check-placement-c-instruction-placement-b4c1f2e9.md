---
bump: minor
---

### Added

- A git pre-commit entry, `index-check`, that fails a commit touching a `.claude/rules/` file or the index file when the generated rules index no longer matches, and prints the regenerate command. A repository with no index block is never failed. `/instruction-placement:setup apply install-git-hooks [scope=local|shared]` registers it with lefthook, husky or plain git hooks, and `check` reports its drift.
- The SessionStart probe reports a missing, stale or edited git-hook entry once per session.

### Changed

- **Breaking:** the per-edit `index-drift` PostToolUse hook and its `index_drift_hook_enabled` option are removed. The model is no longer told about index drift after each rules edit; the pre-commit entry and `/instruction-placement:check` in CI report it instead. Decline the entry per clone with `setup`.
- `render-index.sh` finds `discover.sh` beside itself when run from an installed git-hook copy.
