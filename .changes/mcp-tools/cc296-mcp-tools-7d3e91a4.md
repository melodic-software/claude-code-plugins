---
bump: minor
---

### Changed

- **C4 warns instead of failing on a long description or server `instructions` field.** The Claude Code changelog and docs pages disagree on how much of each tool description and server `instructions` field is kept. C4 now warns past the skill's own length floor, and a new description length record points at the changelog and the docs pages and names where they disagree. The README no longer states the limit.
- **The audit grades against MCP specification 2026-07-28.** That is the revision Claude Code now negotiates by default. A spec revision record says why and when to recheck, and no criterion changed.

### Added

- **C19 recognizes a per-tool `anthropic/alwaysLoad: false`.** That value keeps a heavy tool deferred when a user configures its whole server to load upfront. It is never a finding, and the audit can now suggest it for a large tool on such a server. The client-behavior record points at which server sources honor it.
- **`/mcp-tools:audit-posture` marks `"type": "sdk"` config entries as `skipped-by-client`.** The audit now treats these entries as dead config and does not score them; shadowing of same-name servers in lower scopes is unchanged. Before this change they appeared as live servers. An SDK entries record points at the docs and changelog note on these entries.
