---
bump: major
---

### Removed

- The `/session-flow:audit-sessions` `style` action ([#7573](https://github.com/melodic-software/claude-code-plugins/issues/7573)). Use `/corrections:codify preferences` (corrections plugin) instead. It reads the store as it is, so run `/session-flow:audit-sessions` first to pick up new sessions, and its threshold is the `recurrence.min_occurrences` setting, default 2.

### Added

- `/session-flow:audit-sessions excerpts-only`, a consumer mode like `sweep-only`: it returns the stored typed-turn excerpts as JSON lines with their exit code, runs no collect, refuses `--write-report` and writes nothing.
