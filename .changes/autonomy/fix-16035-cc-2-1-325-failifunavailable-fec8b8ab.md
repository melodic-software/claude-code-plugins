---
bump: patch
---

### Fixed

- setup's Windows surfaces record reads what `sandbox.failIfUnavailable` does at startup, locally and in Anthropic-hosted sessions, from its settings reference section instead of restating it, after Claude Code 2.1.325 added a hosted-session exception (#16035).
