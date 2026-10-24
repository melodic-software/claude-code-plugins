---
bump: patch
---

### Fixed

- `feedback-thread.sh check-paths` and `record` no longer let a lane review-fix edit a plugin's control or instruction files (`.claude-plugin/`, `hooks/`, `monitors/`, `bin/`, `.mcp.json`, `.lsp.json`, `AGENTS.md`, `CLAUDE.md`, `.claude/`) through the plugin-wide scope of a thread on another file in that plugin. The thread's own path and named paths are unchanged.
