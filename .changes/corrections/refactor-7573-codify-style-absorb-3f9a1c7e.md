---
bump: minor
---

### Added

- `/corrections:codify preferences` ([#7573](https://github.com/melodic-software/claude-code-plugins/issues/7573)): with the `session-flow` plugin installed, reads your typed turns through `/session-flow:audit-sessions excerpts-only`, counts each preference by distinct session against `recurrence.min_occurrences`, and proposes each one you confirm as a line for a user-scope file, never a repository file. You add the line yourself.
