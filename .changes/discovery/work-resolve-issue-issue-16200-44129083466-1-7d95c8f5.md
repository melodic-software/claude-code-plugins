---
bump: patch
---

### Changed

- The `explorer` agent's record of how a subagent loads instruction files is now a plain pointer to the probe in [#4157](https://github.com/melodic-software/claude-code-plugins/pull/4157), with no as-of date or recheck trigger. The dropped trigger named Claude Code 2.1.268, a version CI has since moved past ([#16200](https://github.com/melodic-software/claude-code-plugins/issues/16200)).
