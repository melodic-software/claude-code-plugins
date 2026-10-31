---
bump: patch
---

### Fixed

- `/plugin-quality:audit session` again forbids a second parser when the ledger or its `plugin_usage` key is missing: it takes no usage count over the transcript, even when the operator urges one. ([#5819](https://github.com/melodic-software/claude-code-plugins/issues/5819))
