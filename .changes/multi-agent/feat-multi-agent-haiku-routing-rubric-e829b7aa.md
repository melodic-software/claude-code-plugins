---
bump: minor
---

### Added

- `reference/routing-rubric.md` sets the rule for Haiku: no role routes to it until it passes the repository's routing eval ([#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)), and a role that does runs at effort `high`, never `xhigh` or `max`. `/multi-agent:route` adds a note for any role that resolves to haiku, named or inherited from a Haiku session, and still resolves it.

### Changed

- The `retrieval` role's bundled effort is now `medium`, and the `research` workload no longer lowers the worker's effort, so research workers run at the worker's own `medium`.
