---
bump: minor
---

### Changed

- `/plugin-quality:audit session` reads `plugin_usage` from the session's running-retro ledger instead of searching installed plugins for session-flow's parser and running it by path. With no ledger or no key it tells the operator to run `/session-flow:running-retro` and re-run; with session-flow absent it reports the missing capability and the by-name form. ([#5819](https://github.com/melodic-software/claude-code-plugins/issues/5819))
