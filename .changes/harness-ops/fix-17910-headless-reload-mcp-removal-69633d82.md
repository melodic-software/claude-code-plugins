---
bump: patch
---

### Fixed

- `plugins`: the headless `/reload-plugins` note says a removed plugin's MCP server disconnects through the Agent SDK's `reload_plugins` control request on Claude Code 2.1.330, while the typed command still leaves it connected until the next session.
