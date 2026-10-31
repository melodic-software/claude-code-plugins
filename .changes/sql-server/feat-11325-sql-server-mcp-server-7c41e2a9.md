---
bump: minor
---

### Added

- The stdio MCP server (`node src/launch.mjs --config <path> --environment <name>`), bound to one environment and its database allow-list. It exposes exactly three tools, `query`, `list_objects` and `describe_object`, declares `tools` with `listChanged` false and returns the same list on every `tools/list`. A `database` outside the allow-list is refused before the executor runs, an omitted `database` takes the first allowed one, and a statement the reject list refuses comes back as a tool error. The server answers both the stateless 2026-07-28 protocol (`server/discover`, per-request `_meta`) and the `initialize`-based 2025-11-25 protocol.
- This release has no database executor yet: every tool call that passes its checks returns a tool error saying so. Unit tests drive the server through a fake executor.
