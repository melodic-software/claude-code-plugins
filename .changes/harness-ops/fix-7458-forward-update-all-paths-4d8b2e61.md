---
bump: minor
---

### Added

- `/harness-ops:plugins sync` now forward-updates the project and local install records of every other present path, a home directory and a linked worktree included, by running `claude plugin update` from that path, and reads each record back. It stops a path when its `.claude/` settings change across a call. The `Divergences` count no longer sends `converge` a pin that `sync` updated or could update, and the `User-home project records` row lists only the records `update` could not move ([#7458](https://github.com/melodic-software/claude-code-plugins/issues/7458)).
- `fleet-state.sh` reports a new `projectEnabledEntry` field per project/local record, and the sync digest a new `other_paths` field, rendered as the `Updated in other paths`, `Not moved in other paths` and `Would update in other paths` rows.

### Fixed

- `converge` now takes each project's `enabledPlugins` entry from `fleet-state.sh`'s new `projectEnabledEntry` field instead of reading the settings file, and still tells an explicit `false` from no entry.
