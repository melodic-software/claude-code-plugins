---
bump: patch
---

### Changed

- `/ai-briefing:setup apply install-build-deps` no longer restates how the plugin cache and Node ESM behave. It states the rule (install nothing into the installed plugin directory, resolve bare packages without `NODE_PATH`) and points at the Claude Code plugin loading reference and the Node.js ESM docs for the details.
