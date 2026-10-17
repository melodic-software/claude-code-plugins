---
bump: patch
---

### Fixed

- Dependabot merge classifier: read a quoted `dependency-name` (a scoped npm package such as `@anthropic-ai/claude-code`), so a patch or minor npm bump is no longer sent to review as `sources-disagree`.
