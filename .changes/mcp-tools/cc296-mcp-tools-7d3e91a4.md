---
bump: minor
---

### Changed

- **C4 warns instead of failing on a long description or server `instructions` field.** Recent Claude Code releases keep more of each tool description and server `instructions` field than older ones, and the Claude Code docs pages have not caught up with the changelog. C4 now warns past the length every client keeps whole, and a new description length record points at the changelog and the docs pages and names where they disagree. The README no longer states the limit.
- **The audit grades against MCP specification 2026-07-28.** That is the revision Claude Code now negotiates by default. A spec revision record says why and when to recheck, and no criterion changed.

### Added

- **C19 recognizes a per-tool `anthropic/alwaysLoad: false`.** That value keeps a heavy tool deferred when a user configures its whole server to load upfront. It is never a finding, and the audit can now suggest it for a large tool on such a server. The client-behavior record points at which server sources honor it.
- **`/mcp-tools:audit-posture` marks `"type": "sdk"` config entries as `skipped-by-client`.** Claude Code does not load an in-process server from a config file, so the inventory now reports these entries as dead config. They are not scored and do not hide a same-name server in a lower scope. Before this change they appeared as live servers.
