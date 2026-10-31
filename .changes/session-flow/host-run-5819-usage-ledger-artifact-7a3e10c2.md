---
bump: minor
---

### Added

- `/session-flow:running-retro`: each checkpoint, in session or from the observer, stamps the ledger frontmatter with `plugin_usage`, one line of JSON (`{"skills": {"<plugin>:<skill>": <count>}}`) counted over the whole session by the retro parser. The ledger's path, name glob and `session_id` and `plugin_usage` keys are now a documented artifact other plugins read, so they need not find session-flow's parser. ([#5819](https://github.com/melodic-software/claude-code-plugins/issues/5819))
