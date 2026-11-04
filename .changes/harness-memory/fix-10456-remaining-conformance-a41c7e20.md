---
bump: patch
---

### Fixed

- `/harness-memory:audit` and `/harness-memory:stateless` resolve the memory directory from a usable `CLAUDE_CODE_PROJECT_DIR_NAME` set beside `CLAUDE_CONFIG_DIR`.
- The import walker keeps a backslash-escaped space inside a path and no longer counts a quoted path as an import.
- `/harness-memory:stateless status` says when a project or local `autoMemoryDirectory` may not be in effect.
- `/harness-memory:audit` references agree that the `MEMORY.md` strip is the gate's own rule, and no longer restate which tool fires a path-scoped rule or how a directly read `AGENTS.md` differs.
